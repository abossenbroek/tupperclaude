#!/usr/bin/env zsh
# test-build-stage.zsh — _claude_docker_build's staging pipeline, which had no
# coverage at all: both existing build assertions bail out in a guard long
# before any staging happens, so the config whitelist copy, the two host->
# container path rewrites, the secret-scanning warning, the build-arg assembly
# and the `always { }` tmpdir cleanup were all untested.
#
# SAFETY: no image is ever built. run-tests.zsh puts zsh/tests/fake-bin ahead
# of the real docker on $PATH and _claude_docker_build calls `command docker`,
# so `docker build` is recorded as argv and returns. The staged context is
# unobservable afterwards — the function's own `always { }` deletes it — so the
# shim snapshots it to $FAKE_DOCKER_CONTEXT_COPY from inside the fake build,
# which is the only moment it exists. That snapshot is what the assertions
# below read.

emulate -L zsh
setopt local_options noksharrays

source $TC_TEST_LIB
source $TUPPERCLAUDE_TEST_ROOT/tupperclaude.plugin.zsh

cd -- $TC_TEST_WORKDIR || exit 1

local out='' rc=0 ctx=''
local -a reply=()

require_fn _claude_docker_build || { test_summary; return }

# ---- a host $HOME worth staging ---------------------------------------------
#
# $HOME here is the per-case mktemp -d that run-tests.zsh creates; the real one
# is never touched.

command mkdir -p "$HOME/.claude/skills/myskill" "$HOME/.claude/commands" \
                 "$HOME/.claude/plugins/marketplaces/mp" "$HOME/.claude/plugins/cache/c"

print -r -- '{"mcpServers":{"x":{"command":"/opt/homebrew/bin/uvx","args":["/opt/homebrew/bin/uv"]}}}' \
    >"$HOME/.claude.json"
print -r -- '# host CLAUDE.md'        >"$HOME/.claude/CLAUDE.md"
print -r -- '{"theme":"dark"}'        >"$HOME/.claude/settings.json"
print -r -- 'skill body'              >"$HOME/.claude/skills/myskill/SKILL.md"
print -r -- 'command body'            >"$HOME/.claude/commands/mycmd.md"
print -r -- 'marketplace'             >"$HOME/.claude/plugins/marketplaces/mp/x.json"
print -r -- 'cached'                  >"$HOME/.claude/plugins/cache/c/y.json"
print -r -- "{\"path\":\"$HOME/.claude/plugins/foo\"}" \
    >"$HOME/.claude/plugins/installed_plugins.json"
print -r -- "{\"path\":\"$HOME/.claude/marketplaces\"}" \
    >"$HOME/.claude/plugins/known_marketplaces.json"

# Valid JSON on purpose. This file used to hold the bare word `not-a-secret`,
# which the path-rewrite step could not parse — so EVERY build in this file
# emitted "could not rewrite host paths in plugin-catalog-cache.json", and the
# secret-scan assertion below, which merely looked for the word "warning",
# passed on that unrelated line. Deleting the entire secret scan left it green.
print -r -- "{\"catalog\":{\"path\":\"$HOME/.claude/plugins/foo\"}}" \
    >"$HOME/.claude/plugins/plugin-catalog-cache.json"

export FAKE_DOCKER_CONTEXT_COPY="$TC_TEST_WORKDIR/staged"
unset FAKE_DOCKER_IMAGES   # every image "exists", so the playwright base check passes

# ============================================================================
# the staged build context
# ============================================================================

command rm -rf -- "$FAKE_DOCKER_CONTEXT_COPY"
reset_docker_log
out="$(_claude_docker_build arm64 base 2>&1)"
rc=$?
(( rc == 0 ))
check "build/base: returns 0 against a fake docker" $? "rc=$rc" "$out"

ctx="$FAKE_DOCKER_CONTEXT_COPY"
[[ -d $ctx ]]
check "build: a build context directory was staged" $?

if [[ -d $ctx ]]; then
    # --- the whitelist: exactly what the header promises gets copied ---
    [[ -f "$ctx/claude.json" ]]
    check "build: ~/.claude.json is staged as claude.json" $?
    [[ -f "$ctx/Dockerfile" ]]
    check "build: the Dockerfile is staged into the context" $?
    [[ -f "$ctx/claude-settings/CLAUDE.md" ]]
    check "build: ~/.claude/CLAUDE.md is staged" $?
    [[ -f "$ctx/claude-settings/settings.json" ]]
    check "build: ~/.claude/settings.json is staged" $?
    [[ -f "$ctx/claude-settings/skills/myskill/SKILL.md" ]]
    check "build: the skills tree is staged recursively" $?
    [[ -f "$ctx/claude-settings/commands/mycmd.md" ]]
    check "build: the commands tree is staged recursively" $?
    [[ -f "$ctx/claude-settings/plugins/marketplaces/mp/x.json" ]]
    check "build: plugin marketplaces are staged" $?
    [[ -f "$ctx/claude-settings/plugins/cache/c/y.json" ]]
    check "build: the plugin cache is staged" $?

    # --- and what must NOT be: secrets are mounted at run time, never baked ---
    [[ ! -e "$ctx/claude-settings/.credentials.json" ]]
    check "build: the Claude credentials file is never staged into the image" $?
    local -a leaked=("$ctx"/**/(.credentials.json|*.pem|id_rsa|id_ed25519)(N))
    (( ${#leaked} == 0 ))
    check "build: no credential-shaped file leaked into the build context" $? "${leaked[@]}"

    # --- rewrite 1: macOS Homebrew MCP paths -> the container's paths ---
    # The host config runs MCP servers via /opt/homebrew/bin/uvx, which does not
    # exist in the Linux image; without this the baked config produces MCP
    # servers that fail to launch inside every container.
    local staged_json="$(<"$ctx/claude.json")"
    [[ $staged_json != */opt/homebrew/* ]]
    check "build: no /opt/homebrew path survives into the baked claude.json" $? \
        "got: $staged_json"
    [[ $staged_json == */usr/local/bin/uvx* ]]
    check "build: uvx is rewritten to the container path" $? "got: $staged_json"
    [[ $staged_json == */usr/local/bin/uv* ]]
    check "build: uv is rewritten to the container path" $? "got: $staged_json"

    # The uv rewrite must not have mangled uvx into /usr/local/bin/uvx's prefix
    # twice — the two expressions are ordered uvx-first for exactly that reason.
    [[ $staged_json != *'/usr/local/bin/uvx'x* ]]
    check "build: the uv rewrite does not corrupt the uvx path" $? "got: $staged_json"

    # --- rewrite 2: absolute host paths in the plugin registries -> /home/agent ---
    local staged_plugins="$(<"$ctx/claude-settings/plugins/installed_plugins.json")"
    [[ $staged_plugins == */home/agent/.claude* ]]
    check "build: installed_plugins.json is rewritten to the container home" $? \
        "got: $staged_plugins"
    [[ $staged_plugins != *"$HOME/.claude"* ]]
    check "build: no host \$HOME path survives in installed_plugins.json" $? \
        "got: $staged_plugins"

    local staged_known="$(<"$ctx/claude-settings/plugins/known_marketplaces.json")"
    [[ $staged_known != *"$HOME/.claude"* ]]
    check "build: no host \$HOME path survives in known_marketplaces.json" $? \
        "got: $staged_known"

    # --- and no sed backup files left in the image ---
    local -a baks=("$ctx"/**/*claude-docker-bak(N))
    (( ${#baks} == 0 ))
    check "build: no sed backup files are left in the build context" $? "${baks[@]}"
fi

# ============================================================================
# the `always { }` cleanup
# ============================================================================
#
# The staged context lives in an mktemp -d. It must be gone by the time the
# function returns, on every path — otherwise a few dozen builds leave several
# GB of copied config in $TMPDIR.

load_docker_log
records_matching build
local staged_tmpdir=''
if (( ${#reply} >= 1 )); then
    argv_tokens "$reply[1]"
    staged_tmpdir="${reply[-1]}"
fi

[[ -n $staged_tmpdir ]]
check "build: the build context path is the last argv token" $? "got: $staged_tmpdir"
if [[ -n $staged_tmpdir ]]; then
    [[ ! -e $staged_tmpdir ]]
    check "build: the staging tmpdir is removed once the build returns" $? \
        "still present: $staged_tmpdir"
fi

# ...including when the build FAILS. Reachable only since the shim grew
# FAKE_DOCKER_FAIL; this branch was dead code to the suite before.
export FAKE_DOCKER_FAIL='build'
reset_docker_log
out="$(_claude_docker_build arm64 base 2>&1)"
rc=$?
(( rc != 0 ))
check "build: a failing 'docker build' makes the function return non-zero" $? "rc=$rc"
[[ $out == *'tupperclaude: error:'* ]]
check "build: the failure is reported in the house error style" $? "got: $out"
[[ $out == *claude-code-full-arm64* ]]
check "build: the failure names the image that failed" $? "got: $out"

load_docker_log
records_matching build
if (( ${#reply} >= 1 )); then
    argv_tokens "$reply[1]"
    [[ ! -e "${reply[-1]}" ]]
    check "build: the staging tmpdir is removed even when the build fails" $? \
        "still present: ${reply[-1]}"
fi

records_matching image prune
(( ${#reply} == 0 ))
check "build: a failed build does not go on to prune images" $? "${reply[@]}"
records_matching run --rm
(( ${#reply} == 0 ))
check "build: a failed build does not go on to probe tool versions" $? "${reply[@]}"
unset FAKE_DOCKER_FAIL

# ============================================================================
# the docker build argv
# ============================================================================

reset_docker_log
command rm -rf -- "$FAKE_DOCKER_CONTEXT_COPY"
out="$(_claude_docker_build arm64 base 2>&1)"
load_docker_log
records_matching build
(( ${#reply} == 1 ))
check "build/base: exactly one 'docker build'" $? "${#reply} record(s)"

if (( ${#reply} == 1 )); then
    local rec=$reply[1]
    argv_has_pair "$rec" --platform linux/arm64
    check "build/base: --platform linux/arm64" $?
    argv_has_pair "$rec" -t claude-code-full-arm64
    check "build/base: -t claude-code-full-arm64" $?

    # BUILD_DATE is what busts the cache for the layers that install pinned
    # tools; without it a rebuild silently reuses a months-old layer.
    argv_tokens "$rec"
    local -a toks=("${reply[@]}")
    (( ${#${(@M)toks:#BUILD_DATE=*}} == 1 ))
    check "build/base: a BUILD_DATE build-arg is passed" $?

    # BASE_IMAGE belongs only to the playwright variant.
    (( ${#${(@M)toks:#BASE_IMAGE=*}} == 0 ))
    check "build/base: no BASE_IMAGE build-arg for the base variant" $?
    (( ${#${(@M)toks:#INCLUDE_AWS=*}} == 0 ))
    check "build/base: no INCLUDE_AWS build-arg unless the aws option is set" $?

    # The aws answer is stamped on the image, because it changes what is IN the
    # image without changing its tag. Untested, the label shipped as write-only
    # bookkeeping: nothing compared it against the option, so flipping aws on
    # and RUNNING (rather than rebuilding) silently gave you no AWS CLI.
    argv_has_pair "$rec" --label tupperclaude.aws=false
    check "build/base: stamps tupperclaude.aws=false when the option is off" $?

    # -f must point INSIDE the staged context, not at the repo's Dockerfile:
    # the context is what gets sent to the daemon.
    local dashf=''
    local i
    for (( i = 1; i < ${#toks}; i++ )); do
        [[ ${toks[i]} == -f ]] && dashf=${toks[i + 1]}
    done
    [[ -n $dashf && $dashf == "${toks[-1]}/Dockerfile" ]]
    check "build/base: -f points at the Dockerfile inside the staged context" $? \
        "-f $dashf, context ${toks[-1]}"
fi

# --- the aws option adds its build-arg and says so ---
zstyle ':omz:plugins:tupperclaude' aws on
reset_docker_log
out="$(_claude_docker_build arm64 base 2>&1)"
load_docker_log
records_matching build INCLUDE_AWS=1
(( ${#reply} == 1 ))
check "build: the aws option adds --build-arg INCLUDE_AWS=1" $? "${#reply} record(s)"
[[ $out == *AWS* ]]
check "build: the aws option is announced in the output" $? "got: $out"

# The label must TRACK the option, not merely exist: a label stuck at one value
# would satisfy the assertion above and still tell the run path nothing.
records_matching build
if (( ${#reply} == 1 )); then
    argv_has_pair "$reply[1]" --label tupperclaude.aws=true
    check "build: stamps tupperclaude.aws=true when the option is on" $?
else
    not_ok "build: one build record to check the aws label on" "${#reply} record(s)"
fi

# ...but ONLY for the base variant. docker/Dockerfile.playwright declares no
# ARG INCLUDE_AWS — the AWS CLI comes from the base image, which playwright is
# FROM'd on top of — so passing it there earns "one or more build-args were not
# consumed" at the end of a 15-minute build, which is where a user is least
# able to tell a cosmetic warning from a real failure.
reset_docker_log
command rm -rf -- "$FAKE_DOCKER_CONTEXT_COPY"
_claude_docker_build arm64 playwright >/dev/null 2>&1
load_docker_log
records_matching build INCLUDE_AWS=1
(( ${#reply} == 0 ))
check "build/playwright: the aws option does NOT add --build-arg INCLUDE_AWS" $? \
    "${#reply} record(s)"

zstyle -d ':omz:plugins:tupperclaude' aws

# --- the helm major: a value, not a flag --------------------------------------
#
# helm is deliberately outside $_tupperclaude_tools, so it needs its own
# coverage: the build arg rides with the k8s layer that reads it, the label
# tracks the value, and an unrecognised value is refused BEFORE a fifteen-minute
# build rather than by the Dockerfile at the end of one.

# Off by default, and the build arg is meaningless without the layer that reads
# it — passing it anyway earns the unconsumed-build-arg warning.
reset_docker_log
command rm -rf -- "$FAKE_DOCKER_CONTEXT_COPY"
_claude_docker_build arm64 base >/dev/null 2>&1
load_docker_log
records_matching build HELM_MAJOR
(( ${#reply} == 0 ))
check "build: no HELM_MAJOR build-arg when k8s is off" $? "${#reply} record(s)"
records_matching build
if (( ${#reply} == 1 )); then
    argv_has_pair "$reply[1]" --label tupperclaude.helm=3
    check "build: stamps the default helm major even when k8s is off" $?
else
    not_ok "build: one build record to check the helm label on" "${#reply} record(s)"
fi

zstyle ':omz:plugins:tupperclaude' k8s on
zstyle ':omz:plugins:tupperclaude' helm both
reset_docker_log
command rm -rf -- "$FAKE_DOCKER_CONTEXT_COPY"
_claude_docker_build arm64 base >/dev/null 2>&1
load_docker_log
records_matching build HELM_MAJOR=both
(( ${#reply} == 1 ))
check "build: the helm option becomes --build-arg HELM_MAJOR" $? "${#reply} record(s)"
records_matching build
if (( ${#reply} == 1 )); then
    argv_has_pair "$reply[1]" --label tupperclaude.helm=both
    check "build: the helm label tracks the option" $?
else
    not_ok "build: one build record to check the helm label on" "${#reply} record(s)"
fi

# Refused up front. The Dockerfile rejects it too, but only after every layer
# above the k8s one has already run.
zstyle ':omz:plugins:tupperclaude' helm 5
reset_docker_log
command rm -rf -- "$FAKE_DOCKER_CONTEXT_COPY"
out="$(_claude_docker_build arm64 base 2>&1)"
rc=$?
(( rc != 0 ))
check "build: an unrecognised helm value is refused" $? "rc=$rc"
[[ $out == *'must be 3, 4 or both'* ]]
check "build: the helm refusal names the legal values" $? "got: $out"
load_docker_log
records_matching build
(( ${#reply} == 0 ))
check "build: nothing is built when the helm value is refused" $? "${#reply} record(s)"

zstyle -d ':omz:plugins:tupperclaude' helm
zstyle -d ':omz:plugins:tupperclaude' k8s

# --- the playwright variant ---
reset_docker_log
command rm -rf -- "$FAKE_DOCKER_CONTEXT_COPY"
out="$(_claude_docker_build arm64 playwright 2>&1)"
rc=$?
(( rc == 0 ))
check "build/playwright: returns 0 when the base image exists" $? "rc=$rc" "$out"

load_docker_log
records_matching build BASE_IMAGE=claude-code-full-arm64
(( ${#reply} == 1 ))
check "build/playwright: --build-arg BASE_IMAGE names the same-arch base image" $? \
    "${#reply} record(s)"
records_matching build -t claude-code-full-playwright-arm64
(( ${#reply} == 1 ))
check "build/playwright: -t claude-code-full-playwright-arm64" $? "${#reply} record(s)"

if [[ -f "$FAKE_DOCKER_CONTEXT_COPY/Dockerfile" ]]; then
    # The playwright context must carry Dockerfile.playwright's content, staged
    # under the plain name `Dockerfile`.
    local staged_df="$(<"$FAKE_DOCKER_CONTEXT_COPY/Dockerfile")"
    local real_df="$(<"$TUPPERCLAUDE_TEST_ROOT/docker/Dockerfile.playwright")"
    [[ $staged_df == "$real_df" ]]
    check "build/playwright: the staged Dockerfile is docker/Dockerfile.playwright" $?
else
    not_ok "build/playwright: no Dockerfile in the staged context"
fi

# --- the playwright variant with its base image MISSING ---
export FAKE_DOCKER_IMAGES='claude-code-full-playwright-arm64'   # base absent
reset_docker_log
out="$(_claude_docker_build arm64 playwright 2>&1)"
rc=$?
(( rc != 0 ))
check "build/playwright: refuses when the same-arch base image is missing" $? "rc=$rc"
[[ $out == *claude-code-full-arm64* ]]
check "build/playwright: the refusal names the missing base image" $? "got: $out"
load_docker_log
records_matching build
(( ${#reply} == 0 ))
check "build/playwright: no build is attempted without the base image" $? "${reply[@]}"
unset FAKE_DOCKER_IMAGES

# ============================================================================
# the secret scan
# ============================================================================
#
# The baked config is the user's own, so this is a warning and not a refusal.
# The case that surprises people is an MCP server configured with an inline API
# key, which ends up inside an image layer.

print -r -- '{"mcpServers":{"x":{"env":{"API_KEY":"sk-live-abcdef"}}}}' >"$HOME/.claude.json"
reset_docker_log
out="$(_claude_docker_build arm64 base 2>&1)"
rc=$?
# Anchored on the secret scan's own words, not on the mere presence of
# "warning" — any unrelated warning would satisfy that, and one did.
[[ $out == *'key/token-looking'* && $out == *'will be baked into'* ]]
check "build: warns when ~/.claude.json contains a key-shaped field" $? "got: $out"
[[ $out == *registry* || $out == *local* ]]
check "build: the warning says to keep the image local" $? "got: $out"
(( rc == 0 ))
check "build: the secret warning is a warning, not a refusal" $? "rc=$rc"

# The warning text must not itself echo the secret value.
[[ $out != *sk-live-abcdef* ]]
check "build: the warning does not print the secret it found" $? "got: $out"

# ...and it must not fire on a config with no such field.
print -r -- '{"mcpServers":{"x":{"command":"/usr/bin/true"}}}' >"$HOME/.claude.json"
reset_docker_log
out="$(_claude_docker_build arm64 base 2>&1)"
[[ $out != *[Ww]arning*key* ]]
check "build: no secret warning for a config with no key-shaped fields" $? "got: $out"

# ============================================================================
# post-build steps
# ============================================================================

reset_docker_log
out="$(_claude_docker_build arm64 base 2>&1)"
load_docker_log

# A successful build must NOT prune. `docker image prune -f` removes EVERY
# dangling image on the host, other projects' build leftovers included, which
# is far too blunt to run as a side effect of building one image —
# claude-docker-clean --prune is the explicit opt-in for that.
records_matching image prune
(( ${#reply} == 0 ))
check "build: does not prune host-wide dangling images as a build side effect" $? \
    "${reply[@]}"

records_matching run --rm --platform linux/arm64 claude-code-full-arm64
(( ${#reply} >= 1 ))
check "build: probes tool versions in the image it just built" $? "${#reply} record(s)"

# Those probes must be --rm and non-interactive: a `-it` here hangs a build
# script that has no TTY.
local r bad_probe=0
for r in "${reply[@]}"; do
    argv_has "$r" -it && bad_probe=1
done
(( bad_probe == 0 ))
check "build: the tool-version probes are not interactive" $?

test_summary

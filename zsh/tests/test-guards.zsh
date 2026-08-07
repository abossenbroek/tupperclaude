#!/usr/bin/env zsh
# test-guards.zsh — error paths: every one must return non-zero and print a
# fix (see AGENT-BRIEF.md house style: "Every error must end with something
# the user can paste."). Also covers claude-docker-shell with nothing
# running, and invalid arch/variant.
#
# Some of these targets (claude-docker-shell, claude-docker-doctor, ...) are
# owned by other agents building in parallel and may not exist yet. A missing
# autoloaded function fails loudly (command-not-found, non-zero exit) rather
# than crashing this script, so each guard is checked defensively and reports
# a clear not-ok with a reason instead of aborting the whole suite.

emulate -L zsh
setopt local_options noksharrays

source $TC_TEST_LIB
source $TUPPERCLAUDE_TEST_ROOT/tupperclaude.plugin.zsh

cd -- $TC_TEST_WORKDIR || exit 1

# A valid ~/.claude.json baseline, so guards that exercise a later preflight
# step (e.g. the Dockerfile check inside _claude_docker_build, which runs
# AFTER the claude-json check) aren't accidentally testing the wrong guard.
# The "invalid/missing claude.json" section below removes and restores it
# around its own assertions.
print -r -- '{}' >$HOME/.claude.json

# require_fn <name> — ok/not_ok the presence of an autoloadable function
# before trying to call it, so a not-yet-written B-agent target is reported
# as "not yet available" rather than as a mysterious downstream failure.
#
# `${+functions[name]}` is true the moment tupperclaude.zsh registers an
# autoload STUB for it — regardless of whether zsh/functions/<name> exists on
# disk yet. Checking $fpath for the real file is what actually distinguishes
# "written" from "declared but not written".
require_fn() {
    local f dir
    for dir in $fpath; do
        f="$dir/$1"
        [[ -r $f ]] && return 0
    done
    not_ok "$1 is available to call" "not written yet (owned by another agent) — skipping its guard tests"
    return 1
}

# --- missing image -----------------------------------------------------------

export FAKE_DOCKER_IMAGES=''  # nothing "exists" — must be exported: the fake
                               # docker binary is a separate process and only
                               # sees the environment, not shell locals.
export TS_AUTHKEY=tskey-auth-fake

local out
out="$(_claude_docker_run arm64 base 2>&1 1>/dev/null)"
local rc=$?
(( rc != 0 ))
check "missing image: _claude_docker_run returns non-zero" $?
[[ $out == *tupperclaude:\ error:* ]]
check "missing image: error uses house style prefix" $?
[[ $out == *claude-docker-build-arm* ]]
check "missing image: error names the fix (claude-docker-build-arm)" $?

unset FAKE_DOCKER_IMAGES

# --- missing Dockerfile -------------------------------------------------------

zstyle ':omz:plugins:tupperclaude' dockerfile /nonexistent/Dockerfile.does-not-exist
out="$(_claude_docker_build arm64 base 2>&1 1>/dev/null)"
rc=$?
(( rc != 0 ))
check "missing Dockerfile: _claude_docker_build returns non-zero" $?
[[ $out == *tupperclaude:\ error:* ]]
check "missing Dockerfile: error uses house style prefix" $?
[[ $out == *Dockerfile.does-not-exist* ]]
check "missing Dockerfile: error names the missing path" $?
[[ $out == *"zstyle "*dockerfile* ]]
check "missing Dockerfile: fix is a pasteable zstyle line" $?
zstyle -d ':omz:plugins:tupperclaude' dockerfile

# --- invalid ~/.claude.json ---------------------------------------------------

# _claude_docker_check "prints nothing" by contract and reports via the
# _tc_check_* globals instead — so call it directly, NOT inside $( ), which
# would fork a subshell and lose those globals on return.
print -r -- '{not valid json' >$HOME/.claude.json
_claude_docker_check claude-json 2>/dev/null
rc=$?
(( rc != 0 ))
check "invalid claude.json: _claude_docker_check claude-json fails" $?
[[ $_tc_check_detail == *'not valid JSON'* ]]
check "invalid claude.json: detail explains why" $?
(( ${#_tc_check_fix} > 0 ))
check "invalid claude.json: a fix command is offered" $?
rm -f $HOME/.claude.json

# missing ~/.claude.json entirely (the other half of this guard)
_claude_docker_check claude-json 2>/dev/null
rc=$?
(( rc != 0 ))
check "missing claude.json: _claude_docker_check claude-json fails" $?
[[ $_tc_check_detail == *'not found'* ]]
check "missing claude.json: detail says not found" $?

# --- no auth key configured ---------------------------------------------------

unset TS_AUTHKEY
unset CLAUDE_DOCKER_OP_TS_REF
zstyle -d ':omz:plugins:tupperclaude' op-ref

_claude_docker_check authkey
rc=$?
(( rc != 0 ))
check "no auth key: _claude_docker_check authkey fails" $?
(( ${#_tc_check_fix} > 0 ))
check "no auth key: a fix command is offered" $?
[[ ${_tc_check_fix[*]} == *TS_AUTHKEY* ]]
check "no auth key: fix mentions TS_AUTHKEY" $?

# The same guard as it surfaces through a real run under network=tailscale.
# FAKE_DOCKER_IMAGES is unset here (not set to '') so the image check passes
# and the failure we observe is really the authkey check, not a missing image.
out="$(_claude_docker_run arm64 base 2>&1 1>/dev/null)"
rc=$?
(( rc != 0 ))
check "no auth key: _claude_docker_run (tailscale network) returns non-zero" $?

# --- claude-docker-shell with nothing running --------------------------------

if require_fn claude-docker-shell; then
    FAKE_DOCKER_PS=''  # nothing running
    out="$(claude-docker-shell 2>&1 1>/dev/null)"
    rc=$?
    (( rc != 0 ))
    check "claude-docker-shell: nothing running -> returns non-zero" $?
    [[ -n $out ]]
    check "claude-docker-shell: nothing running -> prints something actionable" $?
fi

# --- invalid arch / variant (via the public wrappers, not just ctx) ---------

_claude_docker_run bogus-arch base 2>/dev/null
rc=$?
(( rc != 0 ))
check "invalid arch via _claude_docker_run: returns non-zero" $?

_claude_docker_run arm64 bogus-variant 2>/dev/null
rc=$?
(( rc != 0 ))
check "invalid variant via _claude_docker_run: returns non-zero" $?

_claude_docker_build bogus-arch base 2>/dev/null
rc=$?
(( rc != 0 ))
check "invalid arch via _claude_docker_build: returns non-zero" $?

test_summary

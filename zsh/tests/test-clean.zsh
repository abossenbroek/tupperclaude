#!/usr/bin/env zsh
# test-clean.zsh — claude-docker-clean, the most destructive command in the
# plugin and, until this file existed, the one with zero assertions.
#
# SAFETY, and it is not negotiable: this file never lets claude-docker-clean
# reach a real daemon. run-tests.zsh puts zsh/tests/fake-bin ahead of the real
# docker on $PATH, and clean calls `command docker`, so every removal is
# recorded as argv and nothing else. The final section asserts that property
# directly — that the only `stop`/`rm`/`rmi`/`volume rm` argv issued are the
# fake ones this test set up — so a future refactor that shells out some other
# way fails here rather than on someone's live sidecars.
#
# The bulk of the coverage is --dry-run, which by contract must enumerate the
# full plan and then issue no destructive command at all.

emulate -L zsh
setopt local_options noksharrays

source $TC_TEST_LIB
source $TUPPERCLAUDE_TEST_ROOT/tupperclaude.plugin.zsh

cd -- $TC_TEST_WORKDIR || exit 1

# Declared once, only assigned below (see the query-on-redeclare note in
# lib/harness.zsh).
local out='' rc=0 verb=''
local -a reply=()

require_fn claude-docker-clean || { test_summary; return }

# destructive_records — every `docker` invocation that would change state.
# Sets $reply. Read-only verbs (ps, images, image inspect, volume ls, inspect,
# info, --version) are excluded by construction.
destructive_records() {
    local -a hits=()
    local r
    local -a toks
    for r in $docker_records; do
        local -a reply
        argv_tokens "$r"
        toks=("${reply[@]}")
        case "${toks[1]}" in
            stop|rm|rmi|kill|start|restart|run|build) hits+=("$r") ;;
            volume) [[ ${toks[2]} == rm ]] && hits+=("$r") ;;
            image)  [[ ${toks[2]} == prune ]] && hits+=("$r") ;;
        esac
    done
    reply=("${hits[@]}")
}

# A world with something in it: two sidecars (one UP — the dangerous case), two
# images present and two absent, three volumes.
setup_world() {
    export FAKE_DOCKER_IMAGES='claude-code-full-arm64 claude-code-full-playwright-arm64'
    export FAKE_DOCKER_IMAGE_TABLE='claude-code-full-arm64|latest|9.34GB;claude-code-full-arm64|pre-zsh-port|9.30GB;claude-code-full-playwright-arm64|latest|11.2GB'
    export FAKE_DOCKER_PS_DB='claude-ts-live|ts1|running|Up 22 hours|22 hours|;claude-ts-dead|ts2|exited|Exited (0) 3 days ago|3 days|;sandbox-x|sx1|running|Up 1 hour|1 hour|tupperclaude.arch=arm64,tupperclaude.variant=base,tupperclaude.dir=/tmp/x'
    export FAKE_DOCKER_VOLUMES='claude-ts-state-claude-ts-live claude-ts-sock-claude-ts-live claude-ts-state-claude-ts-dead'
    unset FAKE_DOCKER_PS
}

# ============================================================================
# --help — must work with no daemon and must never enumerate anything
# ============================================================================

export FAKE_DOCKER_FAIL='info'   # daemon unreachable
: >$FAKE_DOCKER_LOG
out="$(claude-docker-clean --help 2>&1)"
rc=$?
(( rc == 0 ))
check "clean --help: exits 0 even with no reachable daemon" $? "rc=$rc"
[[ $out == *--dry-run* && $out == *--force* && $out == *--state* && $out == *--prune* ]]
check "clean --help: documents every option" $? "got: $out"
[[ $out == *credentials* ]]
check "clean --help: says what is never removed" $? "got: $out"

load_docker_log
destructive_records
(( ${#reply} == 0 ))
check "clean --help: issues no destructive docker command" $? "${reply[@]}"
unset FAKE_DOCKER_FAIL

# ============================================================================
# unknown argument
# ============================================================================

: >$FAKE_DOCKER_LOG
out="$(claude-docker-clean --definitely-not-an-option 2>&1)"
rc=$?
(( rc != 0 ))
check "clean: unknown argument returns non-zero" $? "rc=$rc"
[[ $out == *'tupperclaude: error:'* ]]
check "clean: unknown argument uses the house error style" $? "got: $out"
[[ $out == *usage* ]]
check "clean: unknown argument prints usage" $? "got: $out"

load_docker_log
destructive_records
(( ${#reply} == 0 ))
check "clean: a rejected argument removes nothing" $? "${reply[@]}"

# ============================================================================
# no daemon — must fail loudly rather than report a reassuring, wrong zero
# ============================================================================

export FAKE_DOCKER_FAIL='info'
: >$FAKE_DOCKER_LOG
out="$(claude-docker-clean --dry-run 2>&1)"
rc=$?
(( rc != 0 ))
check "clean: unreachable daemon returns non-zero instead of 'nothing to clean'" $? "rc=$rc"
[[ $out != *'0 sidecar'* ]]
check "clean: unreachable daemon does not print an enumeration" $? "got: $out"
unset FAKE_DOCKER_FAIL

# ============================================================================
# --dry-run — the full plan, and NOTHING touched
# ============================================================================

setup_world
: >$FAKE_DOCKER_LOG
out="$(claude-docker-clean --dry-run 2>&1)"
rc=$?
(( rc == 0 ))
check "clean --dry-run: exits 0" $? "rc=$rc" "$out"

[[ $out == *'dry run'* ]]
check "clean --dry-run: says it was a dry run" $? "got: $out"

# --- the plan names each class of resource ---
[[ $out == *claude-ts-live* && $out == *claude-ts-dead* ]]
check "clean --dry-run: names every sidecar, running and stopped" $? "got: $out"

[[ $out == *RUNNING* ]]
check "clean --dry-run: marks the UP sidecar as running" $? "got: $out"
[[ $out == *WARNING* && $out == *'live Claude'* ]]
check "clean --dry-run: warns that removing an UP sidecar kills live sessions" $? "got: $out"

[[ $out == *claude-code-full-arm64* && $out == *claude-code-full-playwright-arm64* ]]
check "clean --dry-run: names the image tags that exist" $? "got: $out"
[[ $out == *'not present, will skip'*claude-code-full-amd64* ]]
check "clean --dry-run: says which image tags are absent" $? "got: $out"
[[ $out == *pre-zsh-port* ]]
check "clean --dry-run: reports non-:latest tags as preserved" $? "got: $out"

[[ $out == *claude-ts-sock-claude-ts-live* && $out == *claude-ts-state-claude-ts-dead* ]]
check "clean --dry-run: names every sidecar volume" $? "got: $out"

[[ $out == *credentials.json* ]]
check "clean --dry-run: lists the preserved credentials" $? "got: $out"

# Without --state and --prune, both must be described as NOT happening.
[[ $out == *'--state'* ]]
check "clean --dry-run: mentions --state as the way to remove state" $? "got: $out"
[[ $out == *'--prune'* ]]
check "clean --dry-run: mentions --prune as opt-in" $? "got: $out"

# --- and the assertion the rest of this section exists for ---
load_docker_log
destructive_records
(( ${#reply} == 0 ))
check "clean --dry-run: issues NO destructive docker command at all" $? "${reply[@]}"

for verb in stop rm rmi run build; do
    records_matching $verb
    (( ${#reply} == 0 ))
    check "clean --dry-run: never issues 'docker $verb'" $? "${reply[@]}"
done
records_matching volume rm
(( ${#reply} == 0 ))
check "clean --dry-run: never issues 'docker volume rm'" $? "${reply[@]}"
records_matching image prune
(( ${#reply} == 0 ))
check "clean --dry-run: never issues 'docker image prune'" $? "${reply[@]}"

# ============================================================================
# --yes with a RUNNING sidecar must refuse without --force
# ============================================================================

setup_world
: >$FAKE_DOCKER_LOG
out="$(claude-docker-clean --yes 2>&1)"
rc=$?
(( rc != 0 ))
check "clean --yes: refuses while a sidecar is UP" $? "rc=$rc"
[[ $out == *refusing*--yes* ]]
check "clean --yes: says why it refused" $? "got: $out"
[[ $out == *--force* ]]
check "clean --yes: names --force as the override" $? "got: $out"

load_docker_log
destructive_records
(( ${#reply} == 0 ))
check "clean --yes: refusal removes nothing" $? "${reply[@]}"

# ============================================================================
# --yes --force — the exact argv it WOULD issue, against the fake docker only
# ============================================================================

setup_world
: >$FAKE_DOCKER_LOG
out="$(claude-docker-clean --yes --force 2>&1)"
rc=$?
(( rc == 0 ))
check "clean --yes --force: exits 0" $? "rc=$rc" "$out"

load_docker_log

# Sandboxes are stopped, by ID, from the labelled ps filter.
records_matching stop sx1
(( ${#reply} == 1 ))
check "clean: stops the labelled sandbox by container ID" $? "${#reply} record(s)"

# Sidecars are removed by NAME with -f, both of them, in one call.
records_matching rm -f claude-ts-live claude-ts-dead
(( ${#reply} == 1 ))
check "clean: removes both sidecars in one 'docker rm -f' by name" $? "${#reply} record(s)"

# Only the images that exist are rmi'd, one call each, and the absent ones are
# never attempted — issuing rmi for an absent tag is what produced the old
# "not present, skipping" lie.
records_matching rmi claude-code-full-arm64
(( ${#reply} == 1 ))
check "clean: rmi's the present base image" $? "${#reply} record(s)"
records_matching rmi claude-code-full-playwright-arm64
(( ${#reply} == 1 ))
check "clean: rmi's the present playwright image" $? "${#reply} record(s)"
records_matching rmi claude-code-full-amd64
(( ${#reply} == 0 ))
check "clean: never rmi's an image it already knows is absent" $? "${reply[@]}"

# Volumes: one `volume rm` per volume, all three, and no others.
local vol
for vol in claude-ts-state-claude-ts-live claude-ts-sock-claude-ts-live claude-ts-state-claude-ts-dead; do
    records_matching volume rm $vol
    (( ${#reply} == 1 ))
    check "clean: removes volume $vol" $? "${#reply} record(s)"
done

# Without --prune it must NOT prune, even on the destructive path: a host-wide
# prune takes other projects' dangling images with it.
records_matching image prune
(( ${#reply} == 0 ))
check "clean --yes --force: does not prune without --prune" $? "${reply[@]}"

# And it must never remove anything outside its own naming scheme.
destructive_records
local -a stray=()
local r
for r in "${reply[@]}"; do
    argv_has "$r" sx1 && continue
    argv_has "$r" claude-ts-live && continue
    argv_has "$r" claude-ts-dead && continue
    argv_has "$r" claude-ts-state-claude-ts-live && continue
    argv_has "$r" claude-ts-sock-claude-ts-live && continue
    argv_has "$r" claude-ts-state-claude-ts-dead && continue
    argv_has "$r" claude-code-full-arm64 && continue
    argv_has "$r" claude-code-full-playwright-arm64 && continue
    stray+=("$r")
done
(( ${#stray} == 0 ))
check "clean: every destructive call targets a resource it enumerated" $? "${stray[@]}"

# ============================================================================
# --prune is opt-in and host-wide
# ============================================================================

setup_world
: >$FAKE_DOCKER_LOG
out="$(claude-docker-clean --dry-run --prune 2>&1)"
[[ $out == *'EVERY dangling image'* ]]
check "clean --prune: the preview says the prune is host-wide" $? "got: $out"

setup_world
: >$FAKE_DOCKER_LOG
out="$(claude-docker-clean --yes --force --prune 2>&1)"
load_docker_log
records_matching image prune -f
(( ${#reply} == 1 ))
check "clean --prune: issues 'docker image prune -f' when asked" $? "${#reply} record(s)"

# ============================================================================
# --state removes per-directory state, and only under --state
# ============================================================================

setup_world
_claude_docker_ctx arm64 base || not_ok "ctx setup for the --state case"
command mkdir -p "$_tc_cfg/instances/some-instance/teams"
print -r -- 'x' >"$_tc_cfg/instances/some-instance/teams/marker"

: >$FAKE_DOCKER_LOG
out="$(claude-docker-clean --dry-run 2>&1)"
[[ -f "$_tc_cfg/instances/some-instance/teams/marker" ]]
check "clean --dry-run: leaves per-directory state on disk" $?
[[ $out == *instances* ]]
check "clean --dry-run: reports the state it found" $? "got: $out"

out="$(claude-docker-clean --yes --force 2>&1)"
[[ -f "$_tc_cfg/instances/some-instance/teams/marker" ]]
check "clean without --state: leaves per-directory state on disk" $?

out="$(claude-docker-clean --yes --force --state 2>&1)"
[[ ! -e "$_tc_cfg/instances" ]]
check "clean --state: removes the per-directory state tree" $?
[[ ! -e "$HOME/.tupperclaude.zsh" || -f "$HOME/.tupperclaude.zsh" ]]
check "clean --state: does not touch anything outside the state root" $?

test_summary

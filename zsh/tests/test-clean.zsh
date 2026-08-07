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
#
# $reply is deliberately NOT declared local, exactly as in records_matching:
# it has to resolve through zsh's dynamic scoping to the CALLER's `local -a
# reply`. A `local -a reply` here (there used to be one, inside the loop)
# shadows it for the whole function, so the closing assignment lands in the
# shadow and the caller keeps whatever the previous records_matching left
# behind — which made "removes nothing" assertions read a stale non-empty
# array and, worse, made genuinely empty results indistinguishable from
# never having been computed.
destructive_records() {
    local -a hits=()
    local r
    local -a toks
    for r in $docker_records; do
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

# Sidecars are removed by NAME with -f, both of them, one call EACH. Batching
# them into a single `docker rm -f a b` is what this used to assert, and it is
# why five sidecars of which three failed counted as one failure and named
# none: the batch call's stderr went to /dev/null. Per-container calls are what
# let the removal loop capture stderr, tell "already gone" from a real error,
# and warn naming the container — the standard the rmi and volume loops already
# held themselves to.
records_matching rm -f claude-ts-live
(( ${#reply} == 1 ))
check "clean: removes the live sidecar in its own 'docker rm -f' by name" $? "${#reply} record(s)"
records_matching rm -f claude-ts-dead
(( ${#reply} == 1 ))
check "clean: removes the dead sidecar in its own 'docker rm -f' by name" $? "${#reply} record(s)"
records_matching rm -f claude-ts-live claude-ts-dead
(( ${#reply} == 0 ))
check "clean: never batches sidecar removals into one call" $? "${reply[@]}"

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

# ============================================================================
# --state must not escape the confirmation guards
#
# The hole this covers: --state is deliberately not a resource SELECTOR, so
# `--volumes --state` left do_containers at 0 — and every guard in the file was
# keyed off container work. at_risk read 0, costly read 0, --yes sailed past
# the refusal, and the single-keypress [y/N] path rm -rf'd <state root>/
# instances while a sandbox had those directories bind-mounted. It is the one
# destructive class here with no rebuild path: an image is a 15-minute rebuild,
# a session's task/team/project history is simply gone.
# ============================================================================

setup_world
_claude_docker_ctx arm64 base || not_ok "ctx setup for the --state guard case"
command mkdir -p "$_tc_cfg/instances/some-instance/teams"
print -r -- 'x' >"$_tc_cfg/instances/some-instance/teams/marker"

# The preview must say so before anything is confirmed.
: >$FAKE_DOCKER_LOG
out="$(claude-docker-clean --dry-run --state 2>&1)"
[[ $out == *WARNING* && $out == *'no rebuild path'* ]]
check "clean --dry-run --state: warns that a live sandbox has this bind-mounted" $? "got: $out"

# setup_world has one running labelled sandbox (sandbox-x/sx1) and --volumes
# means no container is touched — so this is exactly the combination where
# every container-keyed guard reads zero.
: >$FAKE_DOCKER_LOG
out="$(claude-docker-clean --volumes --state --yes 2>&1)"
rc=$?
(( rc != 0 ))
check "clean --volumes --state --yes: refuses while a sandbox is live" $? "rc=$rc" "$out"
[[ $out == *refusing*--yes* ]]
check "clean --volumes --state --yes: refuses in the house error style" $? "got: $out"
[[ $out == *--state* ]]
check "clean --volumes --state --yes: names --state as the reason" $? "got: $out"
[[ $out == *instances* ]]
check "clean --volumes --state --yes: names the state directory at stake" $? "got: $out"
[[ -f "$_tc_cfg/instances/some-instance/teams/marker" ]]
check "clean --volumes --state --yes: the refusal leaves the state on disk" $?

load_docker_log
destructive_records
(( ${#reply} == 0 ))
check "clean --volumes --state --yes: the refusal removes nothing at all" $? "${reply[@]}"

# --force remains the one escape hatch, and even then --volumes must not have
# grown the power to stop a container.
: >$FAKE_DOCKER_LOG
out="$(claude-docker-clean --volumes --state --yes --force 2>&1)"
rc=$?
(( rc == 0 ))
check "clean --volumes --state --yes --force: exits 0" $? "rc=$rc" "$out"
[[ ! -e "$_tc_cfg/instances" ]]
check "clean --volumes --state --yes --force: --force is still the escape hatch" $?

load_docker_log
records_matching stop sx1
(( ${#reply} == 0 ))
check "clean --volumes --state: never stops a sandbox" $? "${reply[@]}"
records_matching rm -f claude-ts-live
(( ${#reply} == 0 ))
check "clean --volumes --state: never removes a sidecar" $? "${reply[@]}"
records_matching rmi claude-code-full-arm64
(( ${#reply} == 0 ))
check "clean --volumes --state: never removes an image" $? "${reply[@]}"

# ============================================================================
# --force on its own is rejected, not silently ignored
# ============================================================================

setup_world
: >$FAKE_DOCKER_LOG
out="$(claude-docker-clean --force 2>&1)"
rc=$?
(( rc != 0 ))
check "clean --force without -y: returns non-zero" $? "rc=$rc"
[[ $out == *'tupperclaude: error:'* && $out == *--force* && $out == *--yes* ]]
check "clean --force without -y: says it only applies with -y" $? "got: $out"

load_docker_log
destructive_records
(( ${#reply} == 0 ))
check "clean --force without -y: removes nothing" $? "${reply[@]}"

# ============================================================================
# an unparseable image size must not read as "free"
#
# The sizes are scraped from docker's human-formatted column ("9.34GB"). When
# that yields nothing, total_bytes stayed 0 — and the typed-`yes` interlock,
# which keys off it, quietly downgraded four multi-hour rebuilds to a single
# keypress. The prompt itself needs a tty and so cannot be asserted here; what
# CAN be asserted is that the preview stops presenting the total as an upper
# bound it no longer is.
# ============================================================================

setup_world
export FAKE_DOCKER_IMAGE_TABLE='claude-code-full-arm64|latest|;claude-code-full-playwright-arm64|latest|'
: >$FAKE_DOCKER_LOG
out="$(claude-docker-clean --dry-run 2>&1)"
[[ $out == *'size unknown'* ]]
check "clean: an image with no reported size is shown as 'size unknown'" $? "got: $out"
[[ $out == *'floor rather than an upper bound'* ]]
check "clean: says the total is a floor when a size could not be parsed" $? "got: $out"
[[ $out != *'freeing up to'* ]]
check "clean: never claims a 'freeing up to' figure it could not measure" $? "got: $out"

# ============================================================================
# an unparseable image size must upgrade the confirmation interlock, not just
# the preview text
#
# --dry-run above proves what gets PRINTED; it never reaches the confirmation
# block at all, so it cannot prove which prompt a live run would show. The
# `read -r`/`read -q` guard three lines above (`[[ ! -t 0 || ! -t 1 ]]`) means
# a plain pipe gets refused outright rather than silently answering the
# prompt — so this has to run on an actual pty, the same trick test-configure
# uses for the wizard, via script(1).
# ============================================================================

# The child the pty runs: source the plugin, run clean, nothing else. Neither
# --yes (skips the prompt entirely) nor --dry-run (never reaches the
# confirmation block) — this must take the real interactive branch. --force
# is rejected on its own (it only unblocks --yes), so it stays off too.
local -r clean_child="$TC_TEST_WORKDIR/clean-child.zsh"
print -r -l -- \
    '#!/usr/bin/env zsh' \
    'source $TUPPERCLAUDE_TEST_ROOT/tupperclaude.plugin.zsh' \
    'claude-docker-clean --images' \
    >$clean_child

# pty_clean <answer> — runs the child on a pty, typing <answer> at whichever
# prompt appears, and returns the transcript text. Same EOF trap as
# pty_wizard: the write end has to outlive the read or macOS's script(1)
# forwards EOF ahead of the buffered answer and the prompt sees an empty
# line instead. The `sleep 2` holding it open must be a REAL two seconds, so
# this file must never set FAKE_SLEEP_MAX (see fake-bin/sleep).
pty_clean() {
    local answer=$1
    local transcript="$TC_TEST_WORKDIR/clean-out-$clean_n.txt"
    (( clean_n++ ))
    {
        if [[ "$(command uname -s)" == Darwin ]]; then
            { print -rn -- "$answer"$'\n\n\n\n'; sleep 2 } | \
                command script -q /dev/null zsh -f $clean_child >$transcript 2>&1
        else
            { print -rn -- "$answer"$'\n\n\n\n'; sleep 2 } | \
                command script -q -c "zsh -f $clean_child" /dev/null >$transcript 2>&1
        fi
    } &
    local spid=$!
    integer waited=0
    while kill -0 $spid 2>/dev/null && (( waited < 40 )); do
        sleep 0.5
        (( waited++ ))
    done
    kill -9 $spid 2>/dev/null
    wait $spid 2>/dev/null
    print -r -- "$transcript"
}
integer clean_n=0

# --images only: do_containers and do_state stay 0, so at_risk and
# state_at_risk are both 0 and `costly` can only come from the images loop —
# isolating exactly the case this defect covered.
export FAKE_DOCKER_IMAGES='claude-code-full-arm64'
export FAKE_DOCKER_IMAGE_TABLE='claude-code-full-arm64|latest|'
export FAKE_DOCKER_PS_DB=''
reset_docker_log
local ct_transcript ct
ct_transcript="$(pty_clean no)"
ct="$(<$ct_transcript)"
[[ $ct != *'not interactive'* && $ct != *"can't open terminal"* ]]
check "clean: the pty for the confirmation-path test satisfies the TTY guard" $? "transcript: $ct"
[[ $ct == *"Type 'yes' to proceed"* ]]
check "clean: an unparseable image size forces the typed-'yes' confirmation, not a keypress" $? "got: $ct"
[[ $ct != *'Continue? [y/N]'* ]]
check "clean: never offers the single-keypress path when a size could not be measured" $? "got: $ct"

load_docker_log
destructive_records
(( ${#reply} == 0 ))
check "clean: declining the typed-'yes' prompt removes nothing" $? "${reply[@]}"

# ============================================================================
# the preserved-credentials paths follow the `home` option
#
# These were three hardcoded ~/.config/claude-docker… strings. Under an
# overridden home they named files the user does not have — on the one promise
# this command makes about what it KEPT, and in the `rm` it hands over to clear
# them. Last section in the file: it exports CLAUDE_DOCKER_HOME.
# ============================================================================

setup_world
# Deliberately OUTSIDE $HOME. Inside it, ${(D)} would shorten the path to
# `~/…` and the assertions could not tell a correctly-resolved root from the
# hardcoded default, which also starts `~/`.
local altroot="$TC_TEST_WORKDIR/relocated-state"
export CLAUDE_DOCKER_HOME="$altroot"

: >$FAKE_DOCKER_LOG
out="$(claude-docker-clean --dry-run 2>&1)"
[[ $out == *"$altroot/.credentials.json"* ]]
check "clean --dry-run: preserves the credentials under the configured home" $? "got: $out"
[[ $out == *"$altroot-playwright/.credentials.json"* ]]
check "clean --dry-run: and the playwright root's credentials too" $? "got: $out"
[[ $out != *'/.config/claude-docker/.credentials.json'* ]]
check "clean --dry-run: never names the default path once home is overridden" $? "got: $out"

# The done block and its `rm` suggestion must agree with the preview — a
# copy-pasteable command pointing at a file the user does not have is worse
# than no suggestion at all.
out="$(claude-docker-clean --yes --force 2>&1)"
[[ $out == *"To clear them: rm "*"$altroot/.credentials.json"* ]]
check "clean: the 'to clear them' rm points at the configured home" $? "got: $out"
[[ $out != *'To clear them: rm ~/.config/claude-docker/'* ]]
check "clean: the rm suggestion is not the hardcoded default" $? "got: $out"

unset CLAUDE_DOCKER_HOME

test_summary

#!/usr/bin/env zsh
# test-ts-ensure.zsh — claude-ts-ensure, which had zero assertions and, worse,
# only ONE reachable branch: the fake docker ignored `inspect -f` entirely, so
# `inspect -f '{{.State.Running}}'` returned empty, no container could ever be
# reported as running, and the socket-volume-recreate, restart-when-offline and
# start-when-stopped paths were invisible to the suite. The shim now honours
# -f/--format, so all four branches are driven here:
#
#   1. nothing exists                    -> create a fresh sidecar
#   2. exists, running, online           -> return 0, touch nothing
#   3. exists, running, OFFLINE          -> restart it
#   4. exists, stopped                   -> start it
#   5. exists but has no socket volume   -> rm -f, then create fresh
#
# Plus the third parameter (the state root), which is NOT derived here on
# purpose: a second, independent derivation is exactly how the resolv.conf came
# to be written to one directory and mounted from another — the bug that killed
# DNS in every playwright + tailscale container.

emulate -L zsh
setopt local_options noksharrays

source $TC_TEST_LIB
source $TUPPERCLAUDE_TEST_ROOT/tupperclaude.plugin.zsh

cd -- $TC_TEST_WORKDIR || exit 1

local out='' err='' rc=0 node=''
local -a reply=()

require_fn claude-ts-ensure || { test_summary; return }

export TS_AUTHKEY=tskey-auth-fake
export FAKE_DOCKER_TS_ONLINE=1

# _claude_ts_online polls once a second and claude-ts-ensure gives it 45 of
# them before giving up, so the offline cases below would cost ~90s of wall
# clock. What they assert is control flow, not duration — see the header of
# zsh/tests/fake-bin/sleep, which caps the wait when this is set.
export FAKE_SLEEP_MAX=0.02

# ============================================================================
# input validation — this is a public command
# ============================================================================
#
# Without the guard, `claude-ts-ensure --help` used to run `docker rm -f --help`
# and then spend 45 seconds printing jq parse errors.

# -h/--help is answered BEFORE the name guard, so it is deliberately NOT in
# this list — see its own case below. Everything here must be rejected.
local bad
for bad in '' '-x' '--nope' 'has space' 'semi;colon' '$(touch pwned)'; do
    reset_docker_log
    err="$(claude-ts-ensure "$bad" 2>&1 1>/dev/null)"
    rc=$?
    (( rc != 0 ))
    check "ts-ensure: rejects container name '${bad:-<empty>}'" $? "rc=$rc"

    load_docker_log
    (( ${#docker_records} == 0 ))
    check "ts-ensure: rejecting '${bad:-<empty>}' runs no docker command at all" $? \
        "${docker_records[@]}"
done

err="$(claude-ts-ensure '' 2>&1 1>/dev/null)"
[[ $err == *'tupperclaude: error:'* ]]
check "ts-ensure: bad input uses the house error style" $? "got: $err"
[[ $err == *claude-ts-ensure* ]]
check "ts-ensure: bad input offers a pasteable example" $? "got: $err"

[[ ! -e "$TC_TEST_WORKDIR/pwned" ]]
check "ts-ensure: a name containing shell metacharacters is never evaluated" $?

# --help must be answered, not treated as a container name. Before the guard
# existed, `claude-ts-ensure --help` ran `docker rm -f --help` and then spent 45
# seconds printing jq parse errors — so the assertion that matters as much as
# the exit status is that it touches no docker at all.
local flag
for flag in -h --help; do
    reset_docker_log
    out="$(claude-ts-ensure $flag 2>&1)"
    rc=$?
    (( rc == 0 ))
    check "ts-ensure $flag: exits 0" $? "rc=$rc"
    [[ $out == *claude-ts-ensure* ]]
    check "ts-ensure $flag: prints usage" $? "got: $out"
    load_docker_log
    (( ${#docker_records} == 0 ))
    check "ts-ensure $flag: runs no docker command" $? "${docker_records[@]}"
done

# ============================================================================
# 1. nothing exists -> create a fresh sidecar
# ============================================================================

node=claude-ts-fresh
unset FAKE_DOCKER_CONTAINERS
reset_docker_log
claude-ts-ensure "$node" ts-hostname >/dev/null 2>&1
rc=$?
(( rc == 0 ))
check "ts-ensure/create: returns 0" $? "rc=$rc"

load_docker_log
records_matching run -d --name "$node"
(( ${#reply} == 1 ))
check "ts-ensure/create: exactly one 'docker run -d' for the sidecar" $? "${#reply} record(s)"

if (( ${#reply} == 1 )); then
    local rec=$reply[1]

    # Kernel networking needs these; without them the sidecar comes up in
    # userspace mode and the joined container's throughput collapses.
    argv_has "$rec" --cap-add=net_admin
    check "ts-ensure/create: --cap-add=net_admin" $?
    argv_has "$rec" --device=/dev/net/tun
    check "ts-ensure/create: --device=/dev/net/tun" $?
    argv_has "$rec" -e
    argv_has "$rec" TS_USERSPACE=false
    check "ts-ensure/create: TS_USERSPACE=false (kernel networking)" $?

    # The node must be persistent, or every launch churns the admin console.
    argv_has_pair "$rec" -v "claude-ts-state-$node:/var/lib/tailscale"
    check "ts-ensure/create: state volume mounted (persistent node identity)" $?
    argv_has "$rec" --restart
    check "ts-ensure/create: --restart policy set" $?

    # The socket volume is what lets the JOINED container run the tailscale CLI
    # at all; a sidecar without it is the case branch 5 below repairs.
    argv_has_pair "$rec" -v "claude-ts-sock-$node:/tmp/tailscale-sock"
    check "ts-ensure/create: socket volume mounted" $?
    argv_has "$rec" TS_SOCKET=/tmp/tailscale-sock/tailscaled.sock
    check "ts-ensure/create: TS_SOCKET points into the socket volume" $?

    argv_has "$rec" "TS_AUTHKEY=$TS_AUTHKEY"
    check "ts-ensure/create: the auth key is passed on first creation" $?
    argv_has "$rec" 'TS_HOSTNAME=ts-hostname'
    check "ts-ensure/create: the tailnet hostname is the one the caller gave" $?
fi

# It must not have tried to start, restart or remove anything.
local verb
for verb in start restart rm; do
    records_matching $verb
    (( ${#reply} == 0 ))
    check "ts-ensure/create: issues no 'docker $verb'" $? "${reply[@]}"
done

# --- a tailnet hostname longer than the 63-byte DNS label cap ---
reset_docker_log
local long_host="${(l:80::x:)}"
claude-ts-ensure claude-ts-longhost "$long_host" >/dev/null 2>&1
load_docker_log
records_matching run -d --name claude-ts-longhost
if (( ${#reply} == 1 )); then
    local -a toks
    argv_tokens "$reply[1]"
    toks=("${reply[@]}")
    local hostarg="${(M)${toks}:#TS_HOSTNAME=*}"
    (( ${#hostarg#TS_HOSTNAME=} <= 63 ))
    check "ts-ensure/create: an over-long tailnet hostname is truncated to <=63 bytes" $? \
        "got ${#hostarg#TS_HOSTNAME=} bytes: $hostarg"
    [[ $hostarg != "TS_HOSTNAME=$long_host" ]]
    check "ts-ensure/create: the over-long hostname was actually shortened" $?
else
    not_ok "ts-ensure/create: no run record for the over-long hostname case"
fi

# ============================================================================
# 2. exists, running and online -> return 0 and touch nothing
# ============================================================================

node=claude-ts-happy
export FAKE_DOCKER_CONTAINERS="$node"
export FAKE_DOCKER_RUNNING="$node"
export FAKE_DOCKER_TS_ONLINE=1
reset_docker_log

claude-ts-ensure "$node" >/dev/null 2>&1
rc=$?
(( rc == 0 ))
check "ts-ensure/online: returns 0 for a healthy sidecar" $? "rc=$rc"

load_docker_log
for verb in run start restart rm; do
    records_matching $verb
    (( ${#reply} == 0 ))
    check "ts-ensure/online: healthy sidecar is not '$verb'ed" $? "${reply[@]}"
done

# ============================================================================
# 3. exists, running, but OFFLINE -> restart
# ============================================================================
#
# The distinction this branch exists for: a sidecar that lost its link to the
# coordination server keeps its 100.x address and still reports
# BackendState=Running, so a container joining its netns silently gets a tailnet
# that resolves nothing.

node=claude-ts-offline
export FAKE_DOCKER_CONTAINERS="$node"
export FAKE_DOCKER_RUNNING="$node"
export FAKE_DOCKER_TS_ONLINE=0
reset_docker_log

out="$(claude-ts-ensure "$node" 2>&1)"
rc=$?
(( rc != 0 ))
check "ts-ensure/offline: returns non-zero when it never comes online" $? "rc=$rc"

load_docker_log
records_matching restart "$node"
(( ${#reply} == 1 ))
check "ts-ensure/offline: restarts the running-but-offline sidecar" $? "${#reply} record(s)"

records_matching run
(( ${#reply} == 0 ))
check "ts-ensure/offline: does NOT create a second sidecar" $? "${reply[@]}"
records_matching rm
(( ${#reply} == 0 ))
check "ts-ensure/offline: does NOT remove the existing sidecar" $? "${reply[@]}"

[[ $out == *offline* || $out == *restart* ]]
check "ts-ensure/offline: says what it is doing" $? "got: $out"
[[ $out == *"did not come online"* ]]
check "ts-ensure/offline: the final error says it never came online" $? "got: $out"
[[ $out == *"docker logs $node"* ]]
check "ts-ensure/offline: the error ends with a pasteable next step" $? "got: $out"

# The health lines from `tailscale status --json` must be surfaced — they are
# the only thing that distinguishes "still starting" from "key expired".
export FAKE_DOCKER_TS_HEALTH='needs login,not in map poll'
reset_docker_log
out="$(claude-ts-ensure "$node" 2>&1)"
[[ $out == *'needs login'* ]]
check "ts-ensure/offline: surfaces the sidecar's reported health" $? "got: $out"
unset FAKE_DOCKER_TS_HEALTH

# ============================================================================
# 4. exists but stopped -> start it
# ============================================================================

node=claude-ts-stopped
export FAKE_DOCKER_CONTAINERS="$node"
export FAKE_DOCKER_RUNNING=''      # exists, not running
export FAKE_DOCKER_TS_ONLINE=1
reset_docker_log

out="$(claude-ts-ensure "$node" 2>&1)"
rc=$?
(( rc == 0 ))
check "ts-ensure/stopped: returns 0 after starting it" $? "rc=$rc" "$out"

load_docker_log
records_matching start "$node"
(( ${#reply} == 1 ))
check "ts-ensure/stopped: starts the existing sidecar" $? "${#reply} record(s)"

records_matching run
(( ${#reply} == 0 ))
check "ts-ensure/stopped: does not create a new one" $? "${reply[@]}"
records_matching rm
(( ${#reply} == 0 ))
check "ts-ensure/stopped: does not remove it first" $? "${reply[@]}"

# Nothing may print a bare `claude-ts-ensure: ...` prefix; the house prefix is
# always `tupperclaude:` so the messages read identically in the fish sibling.
[[ $out != *'claude-ts-ensure:'* ]]
check "ts-ensure/stopped: progress uses the tupperclaude: prefix, not a function name" $? \
    "got: $out"

# ============================================================================
# 5. exists but has no socket volume -> rm -f, then create fresh
# ============================================================================
#
# A sidecar created before the socket volume existed has nothing for the joined
# container to talk to. Recreating is safe because the node identity lives in
# the separate state volume, so it costs nothing in the admin console.

node=claude-ts-nosock
export FAKE_DOCKER_CONTAINERS="$node"
export FAKE_DOCKER_RUNNING="$node"
export FAKE_DOCKER_MOUNTS=''       # no mounts at all
export FAKE_DOCKER_TS_ONLINE=1
reset_docker_log

out="$(claude-ts-ensure "$node" 2>&1)"
rc=$?

load_docker_log
records_matching rm -f "$node"
(( ${#reply} == 1 ))
check "ts-ensure/no-socket-volume: removes the legacy sidecar" $? "${#reply} record(s)"
[[ $out == *recreat* ]]
check "ts-ensure/no-socket-volume: warns that it is recreating the sidecar" $? "got: $out"

# The rm must happen BEFORE the create, or the create fails on a name clash.
local -a all_recs=("${docker_records[@]}")
local i rm_at=0 run_at=0
for (( i = 1; i <= ${#all_recs}; i++ )); do
    argv_tokens "$all_recs[i]"
    [[ ${reply[1]} == rm  && $rm_at  == 0 ]] && rm_at=$i
    [[ ${reply[1]} == run && $run_at == 0 ]] && run_at=$i
done
(( rm_at > 0 && run_at > rm_at ))
check "ts-ensure/no-socket-volume: the rm precedes the re-create" $? "rm at $rm_at, run at $run_at"

# A sidecar that HAS the socket volume must not be recreated.
unset FAKE_DOCKER_MOUNTS
reset_docker_log
claude-ts-ensure "$node" >/dev/null 2>&1
load_docker_log
records_matching rm
(( ${#reply} == 0 ))
check "ts-ensure: a sidecar that already has its socket volume is left alone" $? "${reply[@]}"

# ============================================================================
# the state root is a PARAMETER, never derived
# ============================================================================

node=claude-ts-resolv
export FAKE_DOCKER_CONTAINERS="$node"
export FAKE_DOCKER_RUNNING="$node"
export FAKE_DOCKER_TS_ONLINE=1

# --- omitted: no resolv.conf is written anywhere ---
local probe="$TC_TEST_WORKDIR/state-probe"
command rm -rf -- "$probe"
reset_docker_log
claude-ts-ensure "$node" ts-host >/dev/null 2>&1
[[ ! -e "$probe" ]]
check "ts-ensure: with no state root, nothing is written to one" $?

# --- given: the resolv.conf appears THERE, and is a regular file ---
claude-ts-ensure "$node" ts-host "$probe" >/dev/null 2>&1
rc=$?
(( rc == 0 ))
check "ts-ensure: accepts a state root as the third parameter" $? "rc=$rc"

[[ -f "$probe/tailscale-resolv.conf" ]]
check "ts-ensure: writes tailscale-resolv.conf into the state root it was GIVEN" $? \
    "this is the mount _claude_docker_run bind-mounts over /etc/resolv.conf;" \
    "if it is missing, Docker creates a root-owned empty DIRECTORY there and DNS dies"

if [[ -f "$probe/tailscale-resolv.conf" ]]; then
    local conf="$(<"$probe/tailscale-resolv.conf")"
    [[ $conf == *'nameserver 100.100.100.100'* ]]
    check "ts-ensure: resolv.conf points at the MagicDNS resolver first" $? "got: $conf"
    [[ $conf == *'nameserver 1.1.1.1'* ]]
    check "ts-ensure: resolv.conf has a fallback resolver" $? "got: $conf"
    [[ $conf == *'options timeout:1 attempts:1'* ]]
    check "ts-ensure: resolv.conf bounds the fallback penalty" $? "got: $conf"
fi

# It must create the directory if it is not there yet — the run path calls this
# on a first-ever launch, before anything else has made $_tc_cfg.
command rm -rf -- "$probe"
claude-ts-ensure "$node" ts-host "$probe/deeper/still" >/dev/null 2>&1
[[ -f "$probe/deeper/still/tailscale-resolv.conf" ]]
check "ts-ensure: creates the state root if it does not exist" $?

# --- an unwritable state root must fail loudly, not silently ---
command mkdir -p "$probe/readonly"
command chmod 500 "$probe/readonly"
err="$(claude-ts-ensure "$node" ts-host "$probe/readonly/nested" 2>&1 1>/dev/null)"
rc=$?
(( rc != 0 ))
check "ts-ensure: an unwritable state root fails instead of running the sidecar anyway" $? "rc=$rc"
[[ $err == *'tupperclaude: error:'* ]]
check "ts-ensure: the unwritable-state-root error uses the house style" $? "got: $err"
command chmod 700 "$probe/readonly"

# ============================================================================
# a failing docker
# ============================================================================
#
# Reachable only since the shim grew FAKE_DOCKER_FAIL; before that every
# "docker failed" branch in this function was dead code to the suite.

node=claude-ts-failrun
unset FAKE_DOCKER_CONTAINERS
unset FAKE_DOCKER_RUNNING
export FAKE_DOCKER_FAIL='run'
reset_docker_log
claude-ts-ensure "$node" >/dev/null 2>&1
rc=$?
(( rc != 0 ))
check "ts-ensure: a failing 'docker run' makes it return non-zero" $? "rc=$rc"
unset FAKE_DOCKER_FAIL

# ============================================================================
# missing auth key, on the branch that actually consumes one
# ============================================================================
#
# The key is read ONLY when a sidecar is created for the first time. Refusing to
# run for a missing key that would never be read is a bug, not a safeguard — so
# the stopped-sidecar case below must still succeed without one.

unset TS_AUTHKEY
unset CLAUDE_DOCKER_OP_TS_REF
zstyle -d ':omz:plugins:tupperclaude' op-ref

node=claude-ts-nokey
unset FAKE_DOCKER_CONTAINERS
reset_docker_log
err="$(claude-ts-ensure "$node" 2>&1 1>/dev/null)"
rc=$?
(( rc != 0 ))
check "ts-ensure: creating a sidecar with no auth key fails" $? "rc=$rc"
[[ $err == *TS_AUTHKEY* ]]
check "ts-ensure: the no-auth-key error names TS_AUTHKEY" $? "got: $err"
load_docker_log
records_matching run -d
(( ${#reply} == 0 ))
check "ts-ensure: no sidecar is created without a key" $? "${reply[@]}"

node=claude-ts-existing-nokey
export FAKE_DOCKER_CONTAINERS="$node"
export FAKE_DOCKER_RUNNING=''
export FAKE_DOCKER_TS_ONLINE=1
reset_docker_log
claude-ts-ensure "$node" >/dev/null 2>&1
rc=$?
(( rc == 0 ))
check "ts-ensure: an EXISTING sidecar starts fine with no auth key" $? "rc=$rc"

# ============================================================================
# one variant's sidecar must not vouch for the other's
# ============================================================================
#
# The leniency above — "a sidecar already exists, so no key is needed" — is
# right for doctor, whose question is "can this machine bring up a sidecar at
# all". It is wrong for claude-ts-ensure, which is about to create ONE specific
# node. Asked without a node, the predicate scans BOTH variants' nodes and
# passes if either exists, so a healthy BASE sidecar used to vouch for a
# PLAYWRIGHT one that could not be created — and it was then created with
# TS_AUTHKEY="", a container that can never authenticate and that comes
# straight back because it holds --restart unless-stopped.
#
# Nothing covered this: FAKE_DOCKER_CONTAINERS was only ever set all-or-nothing.

local base_node pw_node
base_node="$(_claude_docker_ctx arm64 base >/dev/null 2>&1 && print -r -- "$_tc_ts_node")"
pw_node="$(_claude_docker_ctx arm64 playwright >/dev/null 2>&1 && print -r -- "$_tc_ts_node")"

[[ -n $base_node && -n $pw_node && $base_node != $pw_node ]]
check "the two variants really have distinct sidecar names" $? "base=$base_node pw=$pw_node"

unset TS_AUTHKEY
unset CLAUDE_DOCKER_OP_TS_REF
zstyle -d ':omz:plugins:tupperclaude' op-ref
export FAKE_DOCKER_CONTAINERS="$base_node"

# The predicate itself, both ways round — this is the property, stated directly.
_claude_docker_check authkey
check "check authkey (no node): any existing sidecar answers doctor's question" $?

_claude_docker_check authkey "$pw_node"
(( $? != 0 ))
check "check authkey <node>: the OTHER variant's sidecar does not vouch for it" $?

_claude_docker_check authkey "$base_node"
check "check authkey <node>: the node's own sidecar does vouch for it" $?

# And end to end: creating the playwright sidecar must be refused, not attempted.
reset_docker_log
err="$(claude-ts-ensure "$pw_node" 2>&1 1>/dev/null)"
rc=$?
(( rc != 0 ))
check "ts-ensure: refuses to create the playwright sidecar on the base one's credit" $? "rc=$rc"
load_docker_log
records_matching run -d
(( ${#reply} == 0 ))
check "ts-ensure: creates no unauthenticatable sidecar in that case" $? "${reply[@]}"

unset FAKE_DOCKER_CONTAINERS

test_summary

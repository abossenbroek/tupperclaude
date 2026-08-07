#!/usr/bin/env zsh
# test-run-args.zsh — asserts the exact `docker run` argv _claude_docker_run
# builds, for all four (arch x variant) combinations, and the two network
# modes. This is the test the fake-docker shim exists for: Claude Code cannot
# be logged in from a test and CI has no daemon, but argv assertions need
# neither.

emulate -L zsh
setopt local_options noksharrays

source $TC_TEST_LIB
source $TUPPERCLAUDE_TEST_ROOT/tupperclaude.plugin.zsh

cd -- $TC_TEST_WORKDIR || exit 1

# Happy path for every preflight check _claude_docker_run performs:
#   - FAKE_DOCKER_IMAGES unset -> `docker image inspect` succeeds for any image
#   - TS_AUTHKEY set -> the tailscale authkey check passes
#   - FAKE_DOCKER_CONTAINERS unset -> claude-ts-ensure always takes the
#     "create a fresh sidecar" branch, and FAKE_DOCKER_TS_ONLINE=1 (default)
#     makes that sidecar report online on the very first poll.
export TS_AUTHKEY=tskey-auth-fake

# --- the four (arch x variant) combinations, network=tailscale (default) ----

local arch variant
for arch in arm64 amd64; do
    for variant in base playwright; do
        : >$FAKE_DOCKER_LOG
        _claude_docker_ctx $arch $variant || { not_ok "$arch/$variant: ctx setup"; continue }
        local want_image=$_tc_image want_name=$_tc_name want_platform=$_tc_platform

        _claude_docker_run $arch $variant
        local run_rc=$?
        check "$arch/$variant: _claude_docker_run exits 0" $run_rc

        load_docker_log
        local -a reply
        records_matching run -it --rm
        local n=${#reply}
        [[ $n -eq 1 ]]
        check "$arch/$variant: exactly one 'docker run -it --rm' invocation" $?

        if (( n >= 1 )); then
            local rec=$reply[1]

            argv_has_pair "$rec" --platform $want_platform
            check "$arch/$variant: --platform $want_platform" $?

            argv_has_pair "$rec" --name $want_name
            check "$arch/$variant: --name $want_name" $?

            argv_has "$rec" $want_image
            check "$arch/$variant: image tag $want_image" $?

            argv_has_pair "$rec" --label "tupperclaude.dir=$PWD"
            check "$arch/$variant: --label tupperclaude.dir" $?
            argv_has_pair "$rec" --label "tupperclaude.arch=$arch"
            check "$arch/$variant: --label tupperclaude.arch" $?
            argv_has_pair "$rec" --label "tupperclaude.variant=$variant"
            check "$arch/$variant: --label tupperclaude.variant" $?

            argv_has "$rec" --ipc=host
            local has_ipc=$?
            if [[ $variant == playwright ]]; then
                check "$arch/playwright: --ipc=host present" $has_ipc
            else
                (( has_ipc != 0 ))
                check "$arch/base: --ipc=host absent" $?
            fi

            argv_has_pair "$rec" -v "$PWD:$PWD"
            check "$arch/$variant: working dir bind-mounted at same absolute path" $?
            argv_has_pair "$rec" -w "$PWD"
            check "$arch/$variant: -w \$PWD" $?

            argv_has_pair "$rec" -v "$_tc_state/teams:/home/agent/.claude/teams"
            check "$arch/$variant: per-directory teams state mount" $?
            argv_has_pair "$rec" -v "$_tc_state/tasks:/home/agent/.claude/tasks"
            check "$arch/$variant: per-directory tasks state mount" $?
            argv_has_pair "$rec" -v "$_tc_state/projects:/home/agent/.claude/projects"
            check "$arch/$variant: per-directory projects state mount" $?

            # network=tailscale (the default: no zstyle, no env override yet)
            argv_has "$rec" "--network=container:$_tc_ts_node"
            check "$arch/$variant: tailscale network flag" $?
            argv_has_pair "$rec" -v "$_tc_cfg/tailscale-resolv.conf:/etc/resolv.conf:ro"
            check "$arch/$variant: tailscale resolv.conf mount" $?
            argv_has_pair "$rec" -v "claude-ts-sock-$_tc_ts_node:/var/run/tailscale"
            check "$arch/$variant: tailscale socket volume mount" $?

            # The assertions above prove only that the right STRINGS were
            # assembled. This one goes to the filesystem: every bind mount's
            # host side must actually exist and be the right kind of thing, or
            # Docker silently creates a root-owned empty directory there. The
            # resolv.conf mount asserted immediately above passed green for a
            # long time while the file it names did not exist for the
            # playwright variant, which killed DNS in every playwright +
            # tailscale container. See check_mounts in lib/harness.zsh.
            check_mounts "$rec" "$arch/$variant"
        else
            not_ok "$arch/$variant: skipping argv assertions, no run record found"
        fi

        # The generated tmux launcher has three windows under tailscale:
        # claude, adc, net.
        local launcher="$_tc_state/tmux-launch.sh"
        [[ -r $launcher ]]
        check "$arch/$variant: tmux launcher was generated" $?
        if [[ -r $launcher ]]; then
            # Always assigned in the same statement: a bare `local windows`
            # redeclared on a later loop iteration, while it still holds a
            # value from the previous one, makes zsh print "windows=<value>"
            # to stdout — its query-on-redeclare behaviour.
            local windows=$(grep -c 'tmux new-session\|tmux new-window' $launcher)
            [[ $windows -eq 3 ]]
            check "$arch/$variant: tailscale tmux launcher has 3 windows" $?
        else
            not_ok "$arch/$variant: tmux launcher missing, cannot count windows"
        fi
    done
done

# --- network mode: default (no tailscale) -----------------------------------

zstyle ':omz:plugins:tupperclaude' network default
: >$FAKE_DOCKER_LOG
_claude_docker_ctx arm64 base || exit 1
_claude_docker_run arm64 base
check "default network: _claude_docker_run exits 0" $?

load_docker_log
local -a reply
records_matching run -it --rm
[[ ${#reply} -eq 1 ]]
check "default network: exactly one 'docker run -it --rm' invocation" $?

if (( ${#reply} == 1 )); then
    local rec=$reply[1]

    argv_has "$rec" "--network=container:$_tc_ts_node"
    (( $? != 0 ))
    check "default network: no --network=container:... flag" $?

    argv_has "$rec" "$_tc_cfg/tailscale-resolv.conf:/etc/resolv.conf:ro"
    (( $? != 0 ))
    check "default network: no resolv.conf mount" $?

    argv_has "$rec" "claude-ts-sock-$_tc_ts_node:/var/run/tailscale"
    (( $? != 0 ))
    check "default network: no tailscale socket-volume mount" $?

    argv_has "$rec" "$_tc_state/netwatch.sh:/run/netwatch.sh:ro"
    (( $? != 0 ))
    check "default network: no netwatch mount" $?

    check_mounts "$rec" "default network"
else
    not_ok "default network: skipping negative argv assertions, no run record found"
fi

local launcher="$_tc_state/tmux-launch.sh"
[[ -r $launcher ]]
check "default network: tmux launcher was generated" $?
if [[ -r $launcher ]]; then
    local windows=$(grep -c 'tmux new-session\|tmux new-window' $launcher)
    [[ $windows -eq 2 ]]
    check "default network: tmux launcher has 2 windows" $?
else
    not_ok "default network: tmux launcher missing, cannot count windows"
fi

zstyle -d ':omz:plugins:tupperclaude' network

test_summary

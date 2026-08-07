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

# --- the aws option vs. the image that is actually there ----------------------
#
# `aws` changes what is IN the image, not its tag, so only a REBUILD acts on it.
# The build stamps the answer it used as a label; the run path compares. Without
# the comparison the label was write-only and flipping the option on, then
# RUNNING rather than rebuilding, silently gave you an image with no AWS CLI.
#
# A warning, never a refusal — the image runs fine, it just isn't what the
# option now says.

_claude_docker_ctx arm64 base || exit 1

# label says false, option says on -> mismatch
export FAKE_DOCKER_IMAGE_LABELS="$_tc_image=tupperclaude.aws=false"
zstyle ':omz:plugins:tupperclaude' aws on
local aws_out
aws_out="$(_claude_docker_run arm64 base 2>&1 1>/dev/null)"
check "aws mismatch: the run still succeeds — this is a warning, not a refusal" $?
# Anchored on both halves of the mismatch — the option's state AND the label's
# — not merely on the substring "aws", which any mention of the option or of a
# host-aws mount would have satisfied whether or not the two were compared.
[[ $aws_out == *'aws option is on'*'built with aws=false'* ]]
check "aws mismatch: the warning states both the option and the label it disagrees with" $? "got: $aws_out"
[[ $aws_out == *claude-docker-build-arm* ]]
check "aws mismatch: the warning names the rebuild command" $? "got: $aws_out"

# label agrees with the option -> silence
export FAKE_DOCKER_IMAGE_LABELS="$_tc_image=tupperclaude.aws=true"
aws_out="$(_claude_docker_run arm64 base 2>&1 1>/dev/null)"
[[ $aws_out != *aws\ option* ]]
check "aws match: no warning when the image agrees with the option" $? "got: $aws_out"
zstyle -d ':omz:plugins:tupperclaude' aws

# No label at all — an image built before the label existed. Silence is the only
# honest answer: there is nothing to compare, and warning on every launch of a
# perfectly good image would train the user to ignore the warning that matters.
export FAKE_DOCKER_IMAGE_LABELS=''
aws_out="$(_claude_docker_run arm64 base 2>&1 1>/dev/null)"
[[ $aws_out != *aws\ option* ]]
check "aws: an image with no label is not accused of a mismatch" $? "got: $aws_out"
unset FAKE_DOCKER_IMAGE_LABELS

# --- aws mismatch: playwright arm (suffix-stripping and base-image comment) ---
#
# The playwright image inherits the aws setting from the base image, so
# rebuilding playwright re-stamps the same (base-decided) value and the warning
# would return forever. The fix command must point to the base builder and carry
# a comment explaining why. This test anchors on the suffix-stripping and the
# comment, not on generic "aws" mentions.

_claude_docker_ctx arm64 playwright || exit 1

export FAKE_DOCKER_IMAGE_LABELS="$_tc_image=tupperclaude.aws=false"
zstyle ':omz:plugins:tupperclaude' aws on
local playwright_aws_out
playwright_aws_out="$(_claude_docker_run arm64 playwright 2>&1 1>/dev/null)"
check "aws mismatch (playwright): the run still succeeds — this is a warning, not a refusal" $?
[[ $playwright_aws_out == *'aws option is on'*'built with aws=false'* ]]
check "aws mismatch (playwright): the warning states both the option and the label it disagrees with" $? "got: $playwright_aws_out"
# Anchored on BOTH the base-image explanation comment AND the stripped command, to prove
# the suffix-stripping ran (not that it fell back to a substring match). The comment is
# the distinguishing marker; "claude-docker-build-arm" alone would match any architect's rebuild.
[[ $playwright_aws_out == *'# the base image decides this; playwright inherits it'* ]]
check "aws mismatch (playwright): the fix command carries the explanation comment" $? "got: $playwright_aws_out"
# The stripping itself, stated directly: offering the -playwright builder here
# would send the user round a loop that re-stamps the inherited value and
# re-emits this same warning. The comment above can survive a wrong command;
# this cannot.
[[ $playwright_aws_out != *claude-docker-build-arm-playwright* ]]
check "aws mismatch (playwright): the fix does NOT name the playwright builder" $? "got: $playwright_aws_out"
zstyle -d ':omz:plugins:tupperclaude' aws
unset FAKE_DOCKER_IMAGE_LABELS

# --- docker-sock, and the gid that travels with it ----------------------------
#
# This option decides whether the sandbox is a security boundary at all: the
# docker socket is root-equivalent on the host. It shipped with NO coverage in
# either state, which is how `--group-add 0` came to be passed unconditionally
# while both the README and the flag's own comment claimed it accompanied the
# mount. Nothing encoded the intent, so the comment was the only statement of
# it — and a comment cannot fail.
#
# The socket must exist on the host for the mount to be added at all, so skip
# rather than assert a falsehood on a machine without one.

if [[ -S /var/run/docker.sock ]]; then
    : >$FAKE_DOCKER_LOG
    _claude_docker_ctx arm64 base || exit 1
    _claude_docker_run arm64 base >/dev/null 2>&1
    load_docker_log
    records_matching run -it --rm
    if (( ${#reply} == 1 )); then
        local sock_rec=$reply[1]
        argv_has_pair "$sock_rec" -v /var/run/docker.sock:/var/run/docker.sock
        check "docker-sock on (default): the socket is mounted" $?
        argv_has_pair "$sock_rec" --group-add 0
        check "docker-sock on (default): --group-add 0 accompanies the mount" $?
    else
        not_ok "docker-sock on: no run record found"
    fi

    zstyle ':omz:plugins:tupperclaude' docker-sock off
    : >$FAKE_DOCKER_LOG
    _claude_docker_run arm64 base >/dev/null 2>&1
    load_docker_log
    records_matching run -it --rm
    if (( ${#reply} == 1 )); then
        local nosock_rec=$reply[1]
        argv_has "$nosock_rec" /var/run/docker.sock:/var/run/docker.sock
        (( $? != 0 ))
        check "docker-sock off: the socket is NOT mounted" $?
        # The point of the option: gid 0 must not survive into the one
        # configuration a user chose in order to tighten the container.
        argv_has "$nosock_rec" --group-add
        (( $? != 0 ))
        check "docker-sock off: --group-add 0 is gone too, not just the mount" $?
    else
        not_ok "docker-sock off: no run record found"
    fi
    zstyle -d ':omz:plugins:tupperclaude' docker-sock
else
    not_ok "docker-sock: skipped — no /var/run/docker.sock on this host to mount"
fi

# --- MACHINE.md ownership -----------------------------------------------------
#
# This is the one thing the run path writes into the user's repository, so who
# owns the file has to be decided structurally. It used to be a substring match
# on the word "tupperclaude", which meant a colleague's own notes that merely
# MENTIONED the tool authorised overwriting them. Ownership is the marker line.

# `command cat`, not zsh's $(<file): the latter is performed even under
# `zsh -n`, so a syntax check of this file would try to open an unset path.
local mmd="$PWD/MACHINE.md" mmd_now=''
local -r user_notes=$'# My notes\n\nWe run this repo under tupperclaude sometimes.\n'

print -rn -- "$user_notes" >$mmd
_claude_docker_run arm64 base >/dev/null 2>&1
mmd_now="$(command cat $mmd)"
[[ "$mmd_now"$'\n' == "$user_notes" ]]
check "MACHINE.md: a user's own file that merely mentions tupperclaude is untouched" $? \
    "got: $mmd_now"

# A file we DID write, naming a different sandbox, must still be refreshed — or
# a base-variant description would keep telling Claude it has no browser after
# switching to playwright.
# A file we DID write, naming a different sandbox, must still be refreshed — or
# a base-variant description would keep telling Claude it has no browser after
# switching to playwright. The refreshed file is then OURS, unedited, and the
# sandbox has exited, so the cleanup removes it: the observable end state is no
# file at all, and "was it refreshed first" is proved by the stale text being
# gone rather than by the file surviving.
print -r -- '<!-- tupperclaude: claude-code-full-arm64 base default -->' >$mmd
print -r -- 'stale' >>$mmd
_claude_docker_run arm64 base >/dev/null 2>&1
[[ ! -e $mmd ]]
check "MACHINE.md: a marked file we refreshed is removed once the sandbox exits" $? \
    "still present: $(command cat $mmd 2>/dev/null)"

# The cleanup must not fire on a file somebody edited. Written by us (so the
# marker matches exactly), then changed by one line — which is what Claude
# appending a note to its own MACHINE.md looks like.
_claude_docker_run arm64 base >/dev/null 2>&1
[[ ! -e $mmd ]]
check "MACHINE.md: an untouched file we wrote is removed on exit" $?

_claude_docker_run arm64 base >/dev/null 2>&1
print -r -- 'a note somebody added' >>$mmd
_claude_docker_run arm64 base >/dev/null 2>&1
[[ -f $mmd ]] && command grep -qF 'a note somebody added' $mmd
check "MACHINE.md: an edited file is kept, not deleted as ours" $? \
    "got: $(command cat $mmd 2>/dev/null)"

command rm -f -- $mmd

# A user's own unmarked file must survive the cleanup as well as the write.
print -rn -- "$user_notes" >$mmd
_claude_docker_run arm64 base >/dev/null 2>&1
mmd_now="$(command cat $mmd 2>/dev/null)"
[[ "$mmd_now"$'\n' == "$user_notes" ]]
check "MACHINE.md: a user's own file survives the exit cleanup" $? \
    "got: $mmd_now"

command rm -f -- $mmd

# --- introspection flags must not start a sandbox ---------------------------
#
# -h/--version are what anyone types at an unfamiliar command. Passing --version
# through to claude ran a real container: it wrote MACHINE.md into the user's
# working directory and, under the default network=tailscale, minted a tailnet
# node — all to answer a question about a version string. The wrappers reserve
# it, and these assert they answer without reaching docker at all.

local want_version="tupperclaude ${TUPPERCLAUDE_VERSION:-unknown}"
local wrapper flag out
for wrapper in claude-docker-arm claude-docker-amd64 \
               claude-docker-arm-playwright claude-docker-amd64-playwright; do
    require_fn $wrapper || continue
    for flag in --version -v; do
        reset_docker_log
        command rm -f -- $mmd

        out="$($wrapper $flag)"
        [[ $out == "$want_version" ]]
        check "$wrapper $flag: prints the tupperclaude version" $? \
            "want: $want_version" "got:  $out"

        load_docker_log
        (( ${#docker_records} == 0 ))
        check "$wrapper $flag: never invokes docker" $? \
            "got ${#docker_records} docker invocation(s)"

        [[ ! -e $mmd ]]
        check "$wrapper $flag: does not write MACHINE.md" $?
    done
done

# The `--` escape has to keep working, or there is no way to ask claude itself
# for its version from inside the sandbox.
reset_docker_log
claude-docker-arm -- --version >/dev/null 2>&1
load_docker_log
local -a reply
records_matching run -it --rm
if (( ${#reply} == 1 )); then
    argv_has "$reply[1]" --version
    check "claude-docker-arm -- --version: --version still reaches claude" $?
else
    not_ok "claude-docker-arm -- --version: --version still reaches claude" \
        "expected exactly one 'docker run -it --rm', got ${#reply}"
fi

# ============================================================================
# The TAIL of the argv — the command the container actually runs.
#
# check_mounts covers the -v set, and the cases above cover the flags, but
# nothing used to look past the image tag. That left the one argv every user
# actually runs unconstrained: dropping "$@", dropping start.sh, or dropping
# every -e credential forward kept the whole suite green. `--version` reaching
# claude and starting a real sandbox shipped through exactly this gap.
# ============================================================================

reset_docker_log
claude-docker-arm --resume xyz >/dev/null 2>&1
load_docker_log
local -a reply
records_matching run -it --rm
if (( ${#reply} == 1 )); then
    local rec="$reply[1]"

    # The passthrough tail, in order. Anchored as a contiguous sequence rather
    # than four independent `argv_has` checks, which would pass on a reordered
    # or interleaved argv.
    argv_has_pair "$rec" claude --teammate-mode
    check "run/tail: claude is invoked with --teammate-mode" $?
    argv_has_pair "$rec" --teammate-mode in-process
    check "run/tail: --teammate-mode carries in-process" $?
    argv_has_pair "$rec" in-process --resume
    check "run/tail: the user's arguments follow, in order" $?
    argv_has_pair "$rec" --resume xyz
    check "run/tail: the user's argument value survives intact" $?

    # The launcher chain: without it the container starts claude directly and
    # the tmux session (and therefore the netwatch window) never exists.
    argv_has "$rec" /usr/local/bin/start.sh
    check "run/tail: the container runs through start.sh" $?

    # The forwarded agent socket. The mount is asserted by check_mounts; this
    # is the env var that makes anything inside the container look at it.
    argv_has_pair "$rec" -e SSH_AUTH_SOCK=/ssh-agent
    check "run/tail: SSH_AUTH_SOCK points at the forwarded socket" $?
else
    not_ok "run/tail: exactly one 'docker run -it --rm'" \
        "got ${#reply}"
fi

# ============================================================================
# The container-name collision guard.
#
# Every case above runs with an empty container table, so `docker ps` returns
# nothing and this guard passed VACUOUSLY across every assertion in this file.
# It is the guard that stops a second `claude-docker-arm` in one directory from
# dying on Docker's raw name conflict — whose obvious remedy, `docker rm -f`,
# kills the live session the user was trying to reach.
# ============================================================================

_claude_docker_ctx arm64 base

export FAKE_DOCKER_PS_DB="$_tc_name|cid1|running|Up 2 hours|2 hours|tupperclaude.arch=arm64"
reset_docker_log
out="$(claude-docker-arm 2>&1)"
rc=$?

(( rc != 0 ))
check "run/collision: refuses while a sandbox is already running here" $? "rc=$rc"

[[ $out == *'already running'* ]]
check "run/collision: the error says a sandbox is already running" $? "got: $out"

[[ $out == *claude-docker-shell* ]]
check "run/collision: it points at claude-docker-shell, not 'docker rm -f'" $? "got: $out"

# The whole point of failing fast: no sidecar work, no MACHINE.md, no run.
load_docker_log
records_matching run -it --rm
(( ${#reply} == 0 ))
check "run/collision: no container is started" $? "got ${#reply} run record(s)"

# A STOPPED container holds the name too — `docker run --name` rejects it just
# the same, so the guard must see it and give different advice.
export FAKE_DOCKER_PS_DB="$_tc_name|cid1|exited|Exited (0) 3 days ago|3 days|tupperclaude.arch=arm64"
reset_docker_log
out="$(claude-docker-arm 2>&1)"
rc=$?

(( rc != 0 ))
check "run/collision: a STOPPED container holding the name also refuses" $? "rc=$rc"

[[ $out == *'docker rm'* ]]
check "run/collision: a stopped holder is offered docker rm" $? "got: $out"

unset FAKE_DOCKER_PS_DB

command rm -f -- $mmd

test_summary

#!/usr/bin/env zsh
# zsh/tests/lib/harness.zsh — shared helpers for test-*.zsh scripts.
#
# `source`d (never autoloaded) by each test-*.zsh, which itself runs inside
# its own `zsh -f` (no rcs, so a developer's own .zshrc cannot leak in) with
# `NO_UNSET WARN_CREATE_GLOBAL`. Every global this file defines is therefore
# declared with `typeset -g`, matching the discipline the code under test is
# held to.
#
# Provides:
#   ok / not_ok / check     TAP-ish assertion output + counters
#   test_summary            trailing "1..N" line; return status = pass/fail
#   require_fn NAME         report a not-yet-written target instead of crashing
#   reset_docker_log        truncate the argv log AND the removal journal
#   load_docker_log         parse $FAKE_DOCKER_LOG into $docker_records
#   argv_tokens RECORD      split one record into $reply (an array)
#   argv_has RECORD TOK     true if TOK appears as a whole argv token
#   argv_has_pair R A B     true if token A is immediately followed by B
#   records_matching TOK... records whose argv[1] is TOK[1] and which also
#                            contain every remaining TOK; sets $reply
#   mount_specs RECORD      every "host:container[:opts]" that followed a -v
#   check_mounts R LABEL    assert every bind mount's HOST side really exists
#                            and is of the expected kind — the one assertion
#                            that goes to the filesystem rather than to argv

emulate -L zsh
setopt local_options

typeset -gi _tc_test_count=0
typeset -gi _tc_test_fail=0

ok() {
    (( _tc_test_count++ ))
    print -r -- "ok $_tc_test_count - $1"
}

not_ok() {
    (( _tc_test_count++ ))
    (( _tc_test_fail++ ))
    print -r -- "not ok $_tc_test_count - $1"
    shift
    local d
    for d in "$@"; do
        print -r -- "#   $d"
    done
}

# check <description> <exit-status> [detail...]
#
# Turns an exit status into an ok/not_ok line. Deliberately takes a status,
# not a command to run: `[[ ... ]]` is shell syntax, not something callable
# as "$@", so the call site is always
#
#   [[ $got == $want ]]
#   check "description" $?
#
# — run the real assertion, then hand its immediate $? to check() before
# anything else can clobber it.
check() {
    local desc=$1 rc=$2
    shift 2
    if (( rc == 0 )); then
        ok "$desc"
    else
        not_ok "$desc" "$@"
    fi
}

# require_fn <name> — ok/not_ok the presence of an autoloadable function
# before trying to call it, so a not-yet-written target is reported as "not
# available" rather than as a mysterious downstream failure. Returns non-zero
# so the caller can skip that section.
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
    not_ok "$1 is available to call" "no $1 found anywhere on \$fpath — skipping its assertions"
    return 1
}

test_summary() {
    print -r -- "1..$_tc_test_count"
    (( _tc_test_fail == 0 ))
}

# --- fake docker argv log ---------------------------------------------------
#
# Format written by zsh/tests/fake-bin/docker: one record per invocation,
# args NUL-separated (so a $PWD containing spaces survives intact), records
# separated by ASCII RS (\x1e). zsh scalars carry embedded NUL bytes fine
# through `"$(<file)"`, so this splits unambiguously.

typeset -ga docker_records

# reset_docker_log — start a case with a clean slate. Truncates BOTH the argv
# log and the shim's removal journal ($FAKE_DOCKER_LOG.removed): a `docker rm`
# recorded by an earlier case would otherwise keep that container "gone" for
# every case after it, in a way `: >$FAKE_DOCKER_LOG` alone does not undo.
reset_docker_log() {
    : >|"$FAKE_DOCKER_LOG"
    : >|"$FAKE_DOCKER_LOG.removed"
    docker_records=()
}

load_docker_log() {
    docker_records=()
    [[ -s $FAKE_DOCKER_LOG ]] || return 0
    local content
    content="$(<$FAKE_DOCKER_LOG)"
    local -a raw
    raw=("${(@ps:\x1e:)content}")
    local r
    for r in $raw; do
        [[ -z $r ]] && continue
        docker_records+=("$r")
    done
}

# argv_tokens RECORD — sets $reply (array). Callers must `local -a reply`
# first: zsh functions are dynamically scoped, so an unqualified assignment
# here lands in the caller's local, per the zsh completion-system convention
# for $reply. Without that local, WARN_CREATE_GLOBAL would flag a leak.
argv_tokens() {
    reply=("${(@ps:\x00:)1}")
    # A trailing NUL after the last real token splits off one empty element.
    (( ${#reply} > 0 )) && [[ -z ${reply[-1]} ]] && reply[-1]=()
}

argv_has() {
    local -a reply
    argv_tokens "$1"
    (( ${reply[(Ie)$2]} ))
}

argv_has_pair() {
    local -a reply
    argv_tokens "$1"
    local i
    for (( i = 1; i < ${#reply}; i++ )); do
        [[ ${reply[i]} == "$2" && ${reply[i + 1]} == "$3" ]] && return 0
    done
    return 1
}

# --- bind-mount assertions ---------------------------------------------------
#
# THE assertion this harness exists for. Asserting that `-v host:container` is
# present in argv proves only that a string was assembled; it says nothing about
# whether the host side is real. Docker's behaviour when it is not is the whole
# problem: a bind mount of a missing host path makes Docker CREATE it — as root,
# and as a DIRECTORY even where a file was meant. Mounting a root-owned empty
# directory over /etc/resolv.conf is how DNS died in every playwright+tailscale
# container while the argv assertion for that exact mount sat green.
#
# So: for every -v in a recorded argv, the host side must exist, and where the
# contract says which kind of thing it is, it must be that kind.
#
# Named volumes (a source with no leading '/') are Docker-managed and have no
# host path to check.

# Container destinations whose host side must be a regular FILE. Anything not
# listed is only checked for existence — this table is the contract, not a
# heuristic, because "has a dot in the basename" gets .cargo and .inputrc wrong
# in opposite directions.
typeset -gA TC_MOUNT_MUST_BE_FILE=(
    /etc/resolv.conf                         1
    /home/agent/.claude/.credentials.json    1
    /home/agent/.tmux.conf                   1
    /home/agent/.inputrc                     1
    /run/tmux-launch.sh                      1
    /run/netwatch.sh                         1
)

# Container destinations whose host side must be a DIRECTORY.
typeset -gA TC_MOUNT_MUST_BE_DIR=(
    /home/agent/.claude/teams     1
    /home/agent/.claude/tasks     1
    /home/agent/.claude/projects  1
    /home/agent/.cargo            1
    /run/host-ssh                 1
    /run/host-gh                  1
    /run/host-gcloud              1
    /run/host-linear              1
    /run/host-pulumi              1
    /run/host-aws                 1
)

# Host paths that legitimately do not exist on macOS and must NOT be checked.
# /run/host-services/ssh-auth.sock lives inside Docker Desktop's Linux VM, which
# synthesises it for the container; see the long comment on the unconditional
# mount in _claude_docker_run. Guarding that mount with a [[ -S ]] test is the
# documented wrong fix, so this test must not demand the file either.
typeset -ga TC_MOUNT_SYNTHETIC=(
    /run/host-services/ssh-auth.sock
)

# mount_specs RECORD — sets $reply to every "host:container[:opts]" that
# followed a -v. Callers must `local -a reply` first (see argv_tokens).
mount_specs() {
    local rec=$1
    argv_tokens "$rec"
    local -a toks=("${reply[@]}") specs=()
    local i
    for (( i = 1; i < ${#toks}; i++ )); do
        [[ ${toks[i]} == -v || ${toks[i]} == --volume ]] && specs+=("${toks[i + 1]}")
    done
    reply=("${specs[@]}")
}

# mount_host_path SPEC — the host side of a "host:container[:opts]" spec.
# Splitting on ':' is not safe here: a host path may legitimately contain one
# (Docker forbids it, but a test that silently mis-parses is worse than one that
# reports the truth), so take the LAST two colon-separated fields as
# container[:opts] and treat everything before as the host path.
mount_host_path() {
    local spec=$1
    local -a f=("${(@s/:/)spec}")
    if (( ${#f} >= 3 )) && [[ ${f[-1]} == (ro|rw|z|Z|ro,z|rw,z|cached|delegated|consistent) ]]; then
        print -r -- "${(j/:/)f[1,-3]}"
    else
        print -r -- "${(j/:/)f[1,-2]}"
    fi
}

mount_container_path() {
    local spec=$1
    local -a f=("${(@s/:/)spec}")
    if (( ${#f} >= 3 )) && [[ ${f[-1]} == (ro|rw|z|Z|ro,z|rw,z|cached|delegated|consistent) ]]; then
        print -r -- "${f[-2]}"
    else
        print -r -- "${f[-1]}"
    fi
}

# check_mounts RECORD LABEL — two assertions over one `docker run` record:
# every bind-mount host path exists, and every one whose kind the contract
# pins down is of that kind. Offenders are listed in the diagnostics, so a
# failure names the exact mount rather than just "something is wrong".
check_mounts() {
    local rec=$1 label=$2
    local -a reply
    mount_specs "$rec"
    local -a specs=("${reply[@]}")
    local -a missing=() wrong_type=()
    local spec host cpath

    for spec in "${specs[@]}"; do
        host="$(mount_host_path "$spec")"
        cpath="$(mount_container_path "$spec")"

        # A named volume, not a bind mount — Docker owns it, nothing to stat.
        [[ $host == /* ]] || continue
        (( ${TC_MOUNT_SYNTHETIC[(Ie)$host]} )) && continue

        if [[ ! -e $host ]]; then
            missing+=("$spec")
            continue
        fi
        if [[ -n ${TC_MOUNT_MUST_BE_FILE[$cpath]:-} && ! -f $host ]]; then
            wrong_type+=("$spec (host side is not a regular file)")
        elif [[ -n ${TC_MOUNT_MUST_BE_DIR[$cpath]:-} && ! -d $host ]]; then
            wrong_type+=("$spec (host side is not a directory)")
        elif [[ $host == "$cpath" && ! -d $host && ! -S $host ]]; then
            # A same-path mount is a working directory or a repo root — with
            # one deliberate exception, /var/run/docker.sock, which is a socket
            # passed through at its own path.
            wrong_type+=("$spec (same-path mount whose host side is not a directory)")
        fi
    done

    (( ${#missing} == 0 ))
    check "$label: every -v host path exists on the host" $? \
        "Docker would create these as root-owned empty DIRECTORIES:" "${missing[@]}"

    (( ${#wrong_type} == 0 ))
    check "$label: every -v host path is of the expected type" $? "${wrong_type[@]}"
}

records_matching() {
    # $reply is deliberately NOT declared local here: it must resolve, via
    # zsh's dynamic scoping, to the caller's `local -a reply` — the same
    # convention argv_tokens relies on. A local reply here would shadow it
    # and the caller would see an empty result.
    local want1=$1
    shift
    local -a matches
    local r
    for r in $docker_records; do
        argv_tokens "$r"
        [[ ${reply[1]} == "$want1" ]] || continue
        # `t=''`, not bare `t`: redeclaring a *bare* local that already
        # holds a value from a previous loop iteration makes zsh print
        # "t=<value>" to stdout (its query-on-redeclare behaviour) — an
        # always-assigned redeclaration never triggers that.
        local all=1 t=''
        for t in "$@"; do
            (( ${reply[(Ie)$t]} )) || { all=0; break }
        done
        (( all )) && matches+=("$r")
    done
    reply=("${matches[@]}")
}

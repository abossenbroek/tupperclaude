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
#   load_docker_log         parse $FAKE_DOCKER_LOG into $docker_records
#   argv_tokens RECORD      split one record into $reply (an array)
#   argv_has RECORD TOK     true if TOK appears as a whole argv token
#   argv_has_pair R A B     true if token A is immediately followed by B
#   records_matching TOK... records whose argv[1] is TOK[1] and which also
#                            contain every remaining TOK; sets $reply

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
        local all=1 t
        for t in "$@"; do
            (( ${reply[(Ie)$t]} )) || { all=0; break }
        done
        (( all )) && matches+=("$r")
    done
    reply=("${matches[@]}")
}

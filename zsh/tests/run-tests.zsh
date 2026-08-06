#!/usr/bin/env zsh
# zsh/tests/run-tests.zsh — runs every zsh/tests/test-*.zsh in isolation and
# reports a combined result.
#
# Each test case runs in its OWN `zsh -f` (no rcs, so a developer's own
# .zshrc cannot leak in) with `NO_UNSET WARN_CREATE_GLOBAL` — a cheap, strict
# check for leaked globals and unset-variable bugs, matching the `typeset -g`
# discipline the code under test is held to. Each case gets its own
# `mktemp -d` $HOME and working directory, with `always { }` cleanup, and its
# own $FAKE_DOCKER_LOG. No Docker daemon is used or required anywhere in this
# suite — see zsh/tests/fake-bin/docker.
#
# A test-*.zsh whose target function doesn't exist yet (other agents are
# writing zsh/functions/* in parallel) fails loudly — command-not-found is a
# normal non-zero exit, not a crash — and is reported as such, not silently
# skipped.

emulate -L zsh
# noksharrays: array indexing throughout assumes 1-based zsh indexing.
# nonomatch:   the test-*.zsh glob below must not error out if it matches
#              nothing (defends against an empty tests/ during early setup).
setopt local_options noksharrays nonomatch

local self_dir=${0:A:h}
typeset -r TC_ROOT=${self_dir:h:h}
typeset -r TC_LIB="$self_dir/lib/harness.zsh"
typeset -r TC_FAKE_BIN="$self_dir/fake-bin"

local -a test_files
test_files=($self_dir/test-*.zsh(N))

if (( ${#test_files} == 0 )); then
    print -u2 "run-tests.zsh: no test-*.zsh files found in $self_dir"
    exit 1
fi

integer total_pass=0 total_fail=0 total_crashed=0

# Declared once, outside the loop, and only ever *assigned* (never
# re-declared) inside it: a bare `local name` (no `=`) redeclared on a later
# loop iteration, while it still holds a value from the previous one, makes
# zsh print "name=<value>" to stdout — its query-on-redeclare behaviour.
local tf name tmphome tmpwork logfile output
integer exit_status file_pass file_fail

for tf in $test_files; do
    name=${tf:t}
    tmphome="$(command mktemp -d)" || exit 1
    tmpwork="$(command mktemp -d)" || exit 1
    logfile="$(command mktemp)" || exit 1

    {
        output="$(
            HOME=$tmphome \
            TUPPERCLAUDE_TEST_ROOT=$TC_ROOT \
            TC_TEST_LIB=$TC_LIB \
            TC_TEST_WORKDIR=$tmpwork \
            FAKE_DOCKER_LOG=$logfile \
            PATH="$TC_FAKE_BIN:$PATH" \
            zsh -f -o NO_UNSET -o WARN_CREATE_GLOBAL -- $tf 2>&1
        )"
        exit_status=$?
    } always {
        command rm -rf -- $tmphome $tmpwork
        command rm -f -- $logfile
    }

    print "=== $name ==="
    print -r -- "$output"

    file_pass=$(print -r -- "$output" | grep -c '^ok ')
    file_fail=$(print -r -- "$output" | grep -c '^not ok ')
    (( total_pass += file_pass, total_fail += file_fail ))

    if [[ "$output" != *$'\n'1..* && "$output" != 1..* ]]; then
        # No "1..N" trailing line at all means the script never reached
        # test_summary — a crash, not a reported failure.
        print "=== $name: CRASHED before finishing (exit $exit_status) ==="
        (( total_crashed++ ))
    elif (( exit_status != 0 && file_fail == 0 )); then
        print "=== $name: exited $exit_status with no 'not ok' lines — investigate ==="
        (( total_crashed++ ))
    fi
    print ""
done

print "-----"
print "total: $total_pass passed, $total_fail failed, $total_crashed crashed (across ${#test_files} files)"

(( total_fail == 0 && total_crashed == 0 ))

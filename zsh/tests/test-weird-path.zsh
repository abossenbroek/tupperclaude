#!/usr/bin/env zsh
# test-weird-path.zsh — the claim lib/harness.zsh and fake-bin/docker both make
# for their NUL-separated record format ("so a $PWD containing spaces survives
# intact") was, until this file existed, never exercised: every other case runs
# under `mktemp -d`, whose paths contain neither spaces nor glob metacharacters.
#
# So this case does its work inside a directory named
#
#     we ird [dir]*name (1)
#
# — spaces, brackets, a glob star, and parentheses — and asserts that what the
# `docker run` argv carries is that exact path, byte for byte, in every place
# _claude_docker_run puts it: the bind mount, -w, the label and
# MISE_TRUSTED_CONFIG_PATHS.
#
# Two distinct properties are on trial here:
#   1. the code under test quotes $PWD correctly (a real product property —
#      `setopt nonomatch` and quoted expansions throughout), and
#   2. the test harness's own record format round-trips it (a property the
#      suite's credibility rests on, since every argv assertion goes through it).
# A failure of either shows up here, and the diagnostics distinguish them.

emulate -L zsh
# noksharrays: 1-based indexing throughout.
# nonomatch:   the weird directory name below must never be glob-expanded.
setopt local_options noksharrays nonomatch

source $TC_TEST_LIB
source $TUPPERCLAUDE_TEST_ROOT/tupperclaude.plugin.zsh

export TS_AUTHKEY=tskey-auth-fake

local -r weird='we ird [dir]*name (1)'
local -r weird_dir="$TC_TEST_WORKDIR/$weird"

command mkdir -p -- "$weird_dir"
[[ -d $weird_dir ]]
check "created a directory named '$weird'" $?

cd -- "$weird_dir" || { not_ok "could not cd into the weird directory"; test_summary; return }

# $PWD may be a /var -> /private/var symlink on macOS; the code uses $PWD as-is,
# so compare against $PWD as-is rather than against the constructed path.
local -r want_pwd=$PWD
[[ $want_pwd == *'we ird [dir]*name (1)' ]]
check "\$PWD really is the weird path" $? "PWD=$want_pwd"

: >$FAKE_DOCKER_LOG
_claude_docker_ctx arm64 base || { not_ok "ctx setup in the weird directory"; test_summary; return }
_claude_docker_run arm64 base
check "_claude_docker_run exits 0 from a weird \$PWD" $?

load_docker_log
local -a reply
records_matching run -it --rm
[[ ${#reply} -eq 1 ]]
check "exactly one 'docker run -it --rm' invocation" $?

if (( ${#reply} == 1 )); then
    local rec=$reply[1]

    # The record format's own round-trip: one argv token must be exactly the
    # weird path, not a fragment of it split on a space.
    argv_tokens "$rec"
    local -a toks=("${reply[@]}")
    (( ${toks[(Ie)$want_pwd]} ))
    check "the weird \$PWD survives as ONE argv token" $? \
        "if this fails, the NUL record format — not the product — is broken" \
        "tokens containing 'we ird': ${(j:, :)${(M)toks:#*we\ ird*}}"

    argv_has_pair "$rec" -v "$want_pwd:$want_pwd"
    check "working dir bind-mounted at the same weird absolute path" $?

    argv_has_pair "$rec" -w "$want_pwd"
    check "-w carries the weird path intact" $?

    argv_has_pair "$rec" --label "tupperclaude.dir=$want_pwd"
    check "--label tupperclaude.dir carries the weird path intact" $?

    argv_has_pair "$rec" -e \
        "MISE_TRUSTED_CONFIG_PATHS=$want_pwd/mise.toml:$want_pwd/.mise.toml:$want_pwd/.mise/config.toml"
    check "MISE_TRUSTED_CONFIG_PATHS carries the weird path intact" $?

    # No token may be a glob-expanded or word-split fragment: the star in the
    # directory name is the dangerous one, since an unquoted expansion under
    # the default NOMATCH would either expand it or abort.
    # (@M) and not (M): a quoted "${(M)array:#pat}" that matches nothing still
    # yields ONE empty element, which would report a phantom fragment.
    local -a fragments=("${(@M)toks:#(we|ird|\[dir\]*name|\(1\))}")
    (( ${#fragments} == 0 ))
    check "no argv token is a word-split fragment of the weird path" $? "${fragments[@]}"

    # And the filesystem check: every host path in this argv must exist, weird
    # name and all. Quoting bugs in mkdir/printf show up here rather than as a
    # root-owned directory in the user's config tree.
    check_mounts "$rec" "weird \$PWD"
fi

# The generated launcher lives under a $_tc_state derived from the weird path.
[[ -r "$_tc_state/tmux-launch.sh" ]]
check "tmux launcher was generated under the weird-path state root" $? \
    "state root: $_tc_state"

test_summary

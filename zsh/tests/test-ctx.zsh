#!/usr/bin/env zsh
# test-ctx.zsh — _claude_docker_ctx produces the exact variant matrix from
# AGENT-BRIEF.md, and rejects invalid arch/variant loudly.
#
# Run in isolation by run-tests.zsh: own $HOME, own $PWD, `zsh -f`,
# `NO_UNSET WARN_CREATE_GLOBAL`.

emulate -L zsh
setopt local_options noksharrays  # array/subscript idioms below assume 1-based indexing

source $TC_TEST_LIB
source $TUPPERCLAUDE_TEST_ROOT/tupperclaude.plugin.zsh

cd -- $TC_TEST_WORKDIR || exit 1

# Deterministic instance suffix: every non-alphanumeric char in $PWD becomes
# '-'. Compute it the same way _claude_docker_ctx does, so this test does not
# hardcode a path-shaped magic string.
local expect_instance=${PWD//[^A-Za-z0-9]/-}
local expect_ts_host="claude-ts-${${PWD:t}//[^A-Za-z0-9]/-}"

# --- the four (arch x variant) combinations ---------------------------------

local arch variant
for arch in arm64 amd64; do
    for variant in base playwright; do
        _claude_docker_ctx $arch $variant
        check "_claude_docker_ctx $arch $variant returns 0" $?

        [[ $_tc_arch == $arch ]]
        check "$arch/$variant: _tc_arch" $?
        [[ $_tc_variant == $variant ]]
        check "$arch/$variant: _tc_variant" $?
        [[ $_tc_platform == "linux/$arch" ]]
        check "$arch/$variant: _tc_platform" $?
        [[ $_tc_instance == $expect_instance ]]
        check "$arch/$variant: _tc_instance" $?
        [[ $_tc_ts_host == $expect_ts_host ]]
        check "$arch/$variant: _tc_ts_host" $?
        [[ $_tc_network == tailscale ]]
        check "$arch/$variant: _tc_network default is tailscale" $?

        if [[ $variant == playwright ]]; then
            [[ $_tc_image == "claude-code-full-playwright-$arch" ]]
            check "$arch/playwright: _tc_image" $?
            [[ $_tc_dockerfile == */docker/Dockerfile.playwright ]]
            check "$arch/playwright: _tc_dockerfile" $?
            [[ $_tc_cfg == $HOME/.config/claude-docker-playwright ]]
            check "$arch/playwright: _tc_cfg" $?
            [[ $_tc_ts_node == claude-ts-pw-$expect_instance ]]
            check "$arch/playwright: _tc_ts_node prefix" $?
            [[ $_tc_name == "claude-docker-playwright-$arch-$expect_instance" ]]
            check "$arch/playwright: _tc_name" $?
            (( ${_tc_run_flags[(Ie)--ipc=host]} > 0 ))
            check "$arch/playwright: _tc_run_flags has --ipc=host" $?
        else
            [[ $_tc_image == "claude-code-full-$arch" ]]
            check "$arch/base: _tc_image" $?
            [[ $_tc_dockerfile == */docker/Dockerfile && $_tc_dockerfile != */Dockerfile.playwright ]]
            check "$arch/base: _tc_dockerfile" $?
            [[ $_tc_cfg == $HOME/.config/claude-docker ]]
            check "$arch/base: _tc_cfg" $?
            [[ $_tc_ts_node == claude-ts-$expect_instance ]]
            check "$arch/base: _tc_ts_node prefix" $?
            [[ $_tc_name == "claude-docker-base-$arch-$expect_instance" ]]
            check "$arch/base: _tc_name" $?
            (( ${#_tc_run_flags} == 0 ))
            check "$arch/base: _tc_run_flags is empty (no --ipc=host)" $?
        fi

        [[ $_tc_state == "$_tc_cfg/instances/$expect_instance" ]]
        check "$arch/$variant: _tc_state under _tc_cfg/instances" $?
    done
done

# playwright and base must never share a state root, or a base and playwright
# sandbox running in the same directory would collide (see _claude_docker_ctx
# comment on Chrome debug ports / dev servers under test).
_claude_docker_ctx arm64 base
local base_cfg=$_tc_cfg
_claude_docker_ctx arm64 playwright
local pw_cfg=$_tc_cfg
[[ $base_cfg != $pw_cfg ]]
check "base and playwright state roots never collapse onto each other" $?

# --- invalid input -----------------------------------------------------------

_claude_docker_ctx bogus-arch base 2>/dev/null
(( $? != 0 ))
check "invalid arch: _claude_docker_ctx returns non-zero" $?

_claude_docker_ctx arm64 bogus-variant 2>/dev/null
(( $? != 0 ))
check "invalid variant: _claude_docker_ctx returns non-zero" $?

local err
err="$(_claude_docker_ctx bogus-arch base 2>&1 1>/dev/null)"
[[ $err == *bogus-arch* ]]
check "invalid arch: error goes to stderr and names the bad value" $?

err="$(_claude_docker_ctx arm64 bogus-variant 2>&1 1>/dev/null)"
[[ $err == *bogus-variant* ]]
check "invalid variant: error goes to stderr and names the bad value" $?

test_summary

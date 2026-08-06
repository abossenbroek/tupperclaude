#!/usr/bin/env zsh
# test-config.zsh — _claude_docker_opt precedence: default < env var < zstyle,
# for both the string and the `-b` boolean forms. Also verifies that a zstyle
# set AFTER the plugin was loaded still takes effect — the property that
# makes .zshrc ordering irrelevant, since every option is read at *call* time.

emulate -L zsh
setopt local_options

source $TC_TEST_LIB
source $TUPPERCLAUDE_TEST_ROOT/tupperclaude.plugin.zsh

local -r ns=':omz:plugins:tupperclaude'

# --- string form: default < env var < zstyle --------------------------------

local v
v="$(_claude_docker_opt madeup-key CLAUDE_DOCKER_TEST_KEY fallback)"
[[ $v == fallback ]]
check "string: no zstyle, no env -> default" $?

CLAUDE_DOCKER_TEST_KEY=from-env
v="$(_claude_docker_opt madeup-key CLAUDE_DOCKER_TEST_KEY fallback)"
[[ $v == from-env ]]
check "string: env var beats default" $?

zstyle "$ns" madeup-key from-zstyle
v="$(_claude_docker_opt madeup-key CLAUDE_DOCKER_TEST_KEY fallback)"
[[ $v == from-zstyle ]]
check "string: zstyle beats env var" $?

zstyle -d "$ns" madeup-key
unset CLAUDE_DOCKER_TEST_KEY

# --- boolean form: default < env var < zstyle --------------------------------

_claude_docker_opt -b madeup-bool CLAUDE_DOCKER_TEST_BOOL
(( $? != 0 ))
check "bool: no zstyle, no env, no default -> false" $?

_claude_docker_opt -b madeup-bool CLAUDE_DOCKER_TEST_BOOL yes
check "bool: no zstyle, no env, default 'yes' -> true" $?

CLAUDE_DOCKER_TEST_BOOL=off
_claude_docker_opt -b madeup-bool CLAUDE_DOCKER_TEST_BOOL yes
(( $? != 0 ))
check "bool: env var 'off' beats default 'yes'" $?

CLAUDE_DOCKER_TEST_BOOL=1
_claude_docker_opt -b madeup-bool CLAUDE_DOCKER_TEST_BOOL
check "bool: env var '1' is true" $?

zstyle "$ns" madeup-bool off
_claude_docker_opt -b madeup-bool CLAUDE_DOCKER_TEST_BOOL
(( $? != 0 ))
check "bool: zstyle 'off' beats env var '1'" $?

zstyle "$ns" madeup-bool on
_claude_docker_opt -b madeup-bool CLAUDE_DOCKER_TEST_BOOL
check "bool: zstyle 'on' beats env var" $?

zstyle -d "$ns" madeup-bool
unset CLAUDE_DOCKER_TEST_BOOL

# -b prints nothing, ever — callers branch on exit status only.
zstyle "$ns" madeup-bool yes
local out
out="$(_claude_docker_opt -b madeup-bool CLAUDE_DOCKER_TEST_BOOL)"
[[ -z $out ]]
check "bool: prints nothing on stdout" $?
zstyle -d "$ns" madeup-bool

# --- zstyle set AFTER the plugin loaded still takes effect -------------------
#
# This is the whole point of reading options at call time rather than at
# plugin-load time: a zstyle line placed anywhere in .zshrc, before or after
# `plugins=(... tupperclaude)`, must work identically. The plugin is already
# sourced above, well before this point, so this exercises exactly that.

v="$(_claude_docker_opt late-key CLAUDE_DOCKER_TEST_LATE before)"
[[ $v == before ]]
check "late zstyle: unset -> falls through to default first" $?

zstyle "$ns" late-key after-load
v="$(_claude_docker_opt late-key CLAUDE_DOCKER_TEST_LATE before)"
[[ $v == after-load ]]
check "late zstyle: a zstyle set after plugin load still wins" $?
zstyle -d "$ns" late-key

test_summary

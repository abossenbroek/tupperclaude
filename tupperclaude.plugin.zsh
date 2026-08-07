#!/usr/bin/env zsh
#
# tupperclaude — oh-my-zsh entry point.
#
# oh-my-zsh sources <dir>/<name>.plugin.zsh at the plugin root; the zsh
# implementation lives under zsh/. This shim bridges the two.
#
# `0=${(%):-%N}` makes $0 this file's path regardless of the user's
# FUNCTION_ARGZERO / POSIX_ARGZERO settings; ${0:A:h} resolves symlinks.
0=${(%):-%N}
source ${0:A:h}/zsh/tupperclaude.zsh

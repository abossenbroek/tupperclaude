#!/usr/bin/env zsh
#
# tupperclaude — oh-my-zsh entry point.
#
# This repo is a monorepo (zsh/, fish/, docker/), but oh-my-zsh loads a plugin by
# sourcing <dir>/<name>.plugin.zsh at the root of the plugin directory. This shim
# forwards to the real zsh implementation so the ordinary clone-and-go install
# works:
#
#   git clone https://github.com/abossenbroek/tupperclaude \
#     ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/tupperclaude
#   plugins=(... tupperclaude)
#
# `0=${(%):-%N}` makes $0 the path of this file regardless of the user's
# FUNCTION_ARGZERO / POSIX_ARGZERO settings; ${0:A:h} then resolves the real
# directory through any symlinks.
0=${(%):-%N}
source ${0:A:h}/zsh/tupperclaude.zsh

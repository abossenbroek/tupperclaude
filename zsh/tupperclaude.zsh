#!/usr/bin/env zsh
#
# tupperclaude (zsh) — run Claude Code in a sandboxed Docker container.
#
# Load is zero-cost: three paths and a set of autoloads. Options resolve at call
# time, so `zstyle` lines work anywhere in .zshrc, before or after the oh-my-zsh
# source line.

0=${(%):-%N}

typeset -g TUPPERCLAUDE_ZSH_DIR=${0:A:h}
typeset -g TUPPERCLAUDE_DIR=${0:A:h:h}
typeset -g TUPPERCLAUDE_VERSION=unknown
[[ -r $TUPPERCLAUDE_DIR/.version ]] && TUPPERCLAUDE_VERSION="$(<$TUPPERCLAUDE_DIR/.version)"

fpath=("$TUPPERCLAUDE_ZSH_DIR/functions" "$TUPPERCLAUDE_ZSH_DIR/completions" $fpath)

# The public commands, shared by the autoload and the compdef below so the two
# cannot drift. A command missing from either fails silently. The private
# _claude_docker_* helpers are autoloaded separately and get no completion.
typeset -ga _tupperclaude_commands=(
    tupperclaude
    claude-docker-arm
    claude-docker-build-arm
    claude-docker-arm-playwright
    claude-docker-build-arm-playwright
    claude-docker-amd64
    claude-docker-build-amd64
    claude-docker-amd64-playwright
    claude-docker-build-amd64-playwright
    claude-docker-doctor
    claude-docker-configure
    claude-docker-clean
    claude-docker-status
    claude-docker-shell
    claude-ts-ensure
)

# The optional toolchains, in the order they appear in the wizard, doctor and
# the tmux window set. Each one changes what is IN the image, so each carries a
# build arg and an image label; _claude_docker_tool derives both from the name.
typeset -ga _tupperclaude_tools=(aws gcloud k8s)

# No compinit here: it is slow and clobbers the first run's cache. But $fpath
# alone is not enough under oh-my-zsh, which adds only the plugin ROOT to $fpath,
# runs compinit, and sources the plugin afterwards — leaving zsh/completions/
# unscanned. compdef records the binding without loading _claude-docker, which
# stays autoloaded from $fpath.
#
# When compinit has not run yet (plugin sourced first), compdef does not exist
# and compinit finds the file on $fpath unaided.
(( ${+functions[compdef]} )) && compdef _claude-docker $_tupperclaude_commands

autoload -Uz \
    $_tupperclaude_commands \
    _claude_docker_build \
    _claude_docker_run \
    _claude_docker_opt \
    _claude_docker_tool \
    _claude_docker_ctx \
    _claude_docker_check \
    _claude_docker_err \
    _claude_docker_help \
    _claude_docker_warn \
    _claude_docker_info \
    _claude_docker_sed_i \
    _claude_ts_online

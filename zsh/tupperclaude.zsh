#!/usr/bin/env zsh
#
# tupperclaude (zsh) — run Claude Code in a sandboxed Docker container.
#
# Loading is deliberately zero-cost: this file only computes three paths and
# registers autoloads. Every option is read at *call* time by the functions
# themselves, never here, so `zstyle` lines work anywhere in .zshrc — before or
# after the oh-my-zsh source line — and a shell that never invokes a
# claude-docker command pays nothing for having the plugin installed.

0=${(%):-%N}

typeset -g TUPPERCLAUDE_ZSH_DIR=${0:A:h}
typeset -g TUPPERCLAUDE_DIR=${0:A:h:h}
typeset -g TUPPERCLAUDE_VERSION=unknown
[[ -r $TUPPERCLAUDE_DIR/.version ]] && TUPPERCLAUDE_VERSION="$(<$TUPPERCLAUDE_DIR/.version)"

fpath=("$TUPPERCLAUDE_ZSH_DIR/functions" $fpath)

autoload -Uz \
    claude-docker-arm \
    claude-docker-arm-build \
    claude-docker-arm-playwright \
    claude-docker-arm-playwright-build \
    claude-docker-amd64 \
    claude-docker-amd64-build \
    claude-docker-amd64-playwright \
    claude-docker-amd64-playwright-build \
    claude-docker-doctor \
    claude-docker-configure \
    claude-docker-clean \
    claude-docker-status \
    claude-docker-shell \
    claude-ts-ensure \
    _claude_docker_build \
    _claude_docker_run \
    _claude_docker_opt \
    _claude_docker_ctx \
    _claude_docker_check \
    _claude_docker_err \
    _claude_docker_warn \
    _claude_docker_sed_i \
    _claude_ts_online

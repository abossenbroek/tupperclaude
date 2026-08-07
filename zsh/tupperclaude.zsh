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

fpath=("$TUPPERCLAUDE_ZSH_DIR/functions" "$TUPPERCLAUDE_ZSH_DIR/completions" $fpath)

# No compinit here on purpose: oh-my-zsh (or the user's own .zshrc) runs it
# once, after plugins have loaded, and calling it a second time is slow and
# clobbers the first run's cache. Prepending to $fpath is all a plugin owes it.

autoload -Uz \
    tupperclaude \
    claude-docker-arm \
    claude-docker-build-arm \
    claude-docker-arm-playwright \
    claude-docker-build-arm-playwright \
    claude-docker-amd64 \
    claude-docker-build-amd64 \
    claude-docker-amd64-playwright \
    claude-docker-build-amd64-playwright \
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
    _claude_docker_help \
    _claude_docker_warn \
    _claude_docker_info \
    _claude_docker_sed_i \
    _claude_ts_online

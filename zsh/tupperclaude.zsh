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

# The public commands: the names a user types, and the exact set the completion
# below is bound to. Kept as an array rather than spelled out twice because the
# compdef call and the autoload call would otherwise drift apart — and a command
# missing from one of them fails silently, which is how the completion bug this
# array exists to fix went unnoticed. The private _claude_docker_* helpers are
# autoloaded separately: they are implementation detail and get no completion.
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

# Still no compinit here — it is slow and clobbers the first run's cache — but
# the $fpath line above is NOT enough on its own under oh-my-zsh.
#
# omz adds the plugin's ROOT directory to $fpath, runs compinit, and only THEN
# sources <plugin>.plugin.zsh (oh-my-zsh.sh: fpath at ~92, compinit at ~129,
# source at ~206). This file therefore runs after compinit has already scanned,
# and zsh/completions/ is a subdirectory omz's root-only convention knows
# nothing about — so `claude-docker-arm<TAB>` completed nothing at all, in every
# shell, for the entire documented install path. Re-running compinit would fix
# it and charge every shell startup for the privilege; binding the completion
# directly costs nothing and fixes it too.
#
# compdef records the binding without loading _claude-docker, which stays
# autoloaded from $fpath on first actual use. The other ordering — a .zshrc that
# sources this file and runs compinit afterwards — needs none of this: compdef
# does not exist yet, and compinit then finds the file on $fpath by itself.
(( ${+functions[compdef]} )) && compdef _claude-docker $_tupperclaude_commands

autoload -Uz \
    $_tupperclaude_commands \
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

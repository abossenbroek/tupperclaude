#!/usr/bin/env zsh
#
# claude-docker — run Claude Code inside a sandboxed Docker container with a
# per-directory Tailscale sidecar.
#
# Commands provided:
#   claude-docker-build-arm     build the linux/arm64 image
#   claude-docker-build-amd64   build the linux/amd64 image
#   claude-docker-arm           run Claude Code in the linux/arm64 image
#   claude-docker-amd64         run Claude Code in the linux/amd64 image
#   claude-ts-ensure            (helper) bring up the Tailscale sidecar
#
# See README.md for configuration.

CLAUDE_DOCKER_PLUGIN_DIR="${0:A:h}"

fpath=("$CLAUDE_DOCKER_PLUGIN_DIR/functions" $fpath)

autoload -Uz \
    claude-docker-build-arm \
    claude-docker-build-amd64 \
    claude-docker-arm \
    claude-docker-amd64 \
    claude-ts-ensure \
    _claude_docker_build \
    _claude_docker_run \
    _claude_docker_sed_i \
    _claude_ts_online

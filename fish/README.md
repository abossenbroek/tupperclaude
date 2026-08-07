# tupperclaude for fish

Planned, not yet implemented.

When ready, this will install as a [fisher](https://github.com/jorgebucaran/fisher)
plugin, including directly from a local clone (fisher supports local-directory
installs):

```fish
fisher install <path-to-clone>/fish
```

It will share `docker/` and all host state (`~/.config/claude-docker` and its
`-playwright` sibling — or wherever `home` points — the cargo cache, and the sandbox's
own Claude credentials file) with the zsh plugin in this repo; both can be installed
side by side and used interchangeably on the same machine — run
`claude-docker-arm` from either shell against the same images and the same per-directory
state.

It will expose the same commands as the zsh plugin: the `tupperclaude` dispatcher, the
verb-first build commands (`claude-docker-build-arm`, `claude-docker-build-amd64`, and
their `-playwright` siblings), the run commands (`claude-docker-arm`,
`claude-docker-amd64`, `-playwright`), and the utilities (`claude-docker-doctor`,
`-configure`, `-status`, `-shell`, `-clean`).

The zsh plugin's **diagnostics** already carry a shell-neutral `tupperclaude:` prefix
rather than a zsh-specific one, and those read identically here: everything routed through
`_claude_docker_err` (`tupperclaude: error: …`), `_claude_docker_warn`
(`tupperclaude: warning: …`) and `_claude_docker_info` (`tupperclaude: …`). Plenty of
other output is deliberately bare, though: the build's per-tool version sweep, the
wizard's preflight table, doctor's report and config block, and `claude-docker-clean`'s
teardown plan are written bare with `print`/`printf` rather than the prefix helpers, and
the wizard's questions are `read -r "key?…"` prompts. A fish port has to reproduce all of
that too, and none of it comes free with the helpers.

The zsh plugin's configuration lives in `zstyle ':omz:plugins:tupperclaude' <key>` lines
with `CLAUDE_DOCKER_*` environment-variable fallbacks. fish has no `zstyle`; the fish
implementation will read the environment variables; the `~/.tupperclaude.zsh` file
written by `claude-docker-configure` is zsh-only and will need a fish equivalent.

See [README.md](../README.md) at the repo root for what tupperclaude does.

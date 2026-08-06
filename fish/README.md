# tupperclaude for fish

Planned, not yet implemented.

When ready, this will install as a [fisher](https://github.com/jorgebucaran/fisher)
plugin, including directly from a local clone (fisher supports local-directory
installs):

```fish
fisher install <path-to-clone>/fish
```

It will share `docker/` and all host state (`~/.config/claude-docker`, the cargo cache,
credentials) with the zsh plugin in this repo, so both can be installed side by side and
used interchangeably on the same machine — run `claude-docker-arm` from either shell
against the same images and the same per-directory state.

See [README.md](../README.md) at the repo root for what tupperclaude does; the fish
implementation will expose the same commands and configuration surface.

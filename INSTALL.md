# Installing tupperclaude

## Requirements

- macOS with **Docker Desktop** (the run commands rely on Docker Desktop's Linux VM for
  `/dev/net/tun` when using `network=tailscale`, and on its ssh-agent forwarding socket
  at `/run/host-services/ssh-auth.sock`)
- `zsh`
- `jq`, `git` (plus `sed`, `awk`, `grep`, `shasum`, `column` — all stock on macOS)
- Claude Code installed and signed in on the host (the build reads `~/.claude.json`)
- A Tailscale account and a **reusable, tagged** auth key — required unless you opt out
  with `network default`. Tailscale **is** the default; see
  [Getting started](README.md#getting-started) for the no-account path.

## Monorepo layout

This repo holds both a zsh plugin and a (planned) fish plugin, sharing `docker/` and all
host state. oh-my-zsh and most zsh plugin managers expect a single entry-point file at
the root of the plugin directory named `<plugin-dir-name>.plugin.zsh`. That file is
`tupperclaude.plugin.zsh` at the repo root — it's a thin shim that forwards to the real
implementation in `zsh/tupperclaude.zsh`. You don't need to know this to install the
plugin; it's why the ordinary clone-into-plugins-dir workflow below just works.

## oh-my-zsh

```zsh
git clone https://github.com/abossenbroek/tupperclaude \
  ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/tupperclaude
```

Add it to your plugin list in `~/.zshrc`:

```zsh
plugins=(... tupperclaude)
```

Then `exec zsh`.

## zinit

zinit sources a specific file rather than resolving a plugin directory convention, so
point it at the root shim:

```zsh
zinit light abossenbroek/tupperclaude
```

zinit's default `as"plugin"` mode already discovers `*.plugin.zsh` at a repo root, which
this repo has. Do **not** add `as"program"` — that treats the repo as a binary, puts its
directory on `$PATH` and never sources anything, so no command is defined.

## antigen

```zsh
antigen bundle abossenbroek/tupperclaude
```

## zplug

```zsh
zplug "abossenbroek/tupperclaude", use:"tupperclaude.plugin.zsh"
```

## Manual (no plugin manager)

```zsh
git clone https://github.com/abossenbroek/tupperclaude ~/.tupperclaude
echo 'source ~/.tupperclaude/tupperclaude.plugin.zsh' >> ~/.zshrc
exec zsh
```

## After installing

```zsh
claude-docker-configure   # interactive setup — recommended first step
claude-docker-doctor      # verify prerequisites
claude-docker-build-arm   # first build (Apple Silicon; use amd64-build on Intel)
claude-docker-arm
```

See [README.md](README.md) for the full command table and configuration reference.

## Uninstall

1. Remove the plugin line:
   - **oh-my-zsh:** delete `tupperclaude` from `plugins=(...)` in `~/.zshrc`, then
     `rm -rf ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/tupperclaude`
   - **zinit:** `zinit delete abossenbroek/tupperclaude`
   - **antigen / zplug:** remove the `bundle`/`zplug` line and remove the cached clone
     per your manager's own cache-clear command
   - **manual:** remove the `source` line from `~/.zshrc` and `rm -rf ~/.tupperclaude`
2. Remove containers, sidecars, and state:

   ```zsh
   claude-docker-clean
   ```

   or manually:

   ```zsh
   docker rm -f $(docker ps -aq --filter label=tupperclaude.dir) 2>/dev/null
   docker ps -a --filter name=claude-ts- -q | xargs -r docker rm -f
   rm -rf ~/.config/claude-docker ~/.config/claude-docker-playwright
   ```

3. Verify nothing was missed — **both** of these should print nothing:

   ```zsh
   docker ps -a --filter label=tupperclaude.dir --format '{{.Names}}'   # sandboxes
   docker ps -a --filter name=claude-ts- --format '{{.Names}}'          # sidecars
   ```

   They must be two separate commands. Docker ANDs filters of different keys, and sidecars
   carry no `tupperclaude.dir` label — so combining them into one command always prints
   nothing and would give you a false all-clear.

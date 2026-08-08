# Installing tupperclaude

tupperclaude is **macOS-only** and currently at version `0.1.0-dev` — a prerelease.
Command names and options may still change.

## Requirements

- macOS with **Docker Desktop** (the run commands rely on Docker Desktop's Linux VM for
  `/dev/net/tun` when using `network=tailscale`, and on its ssh-agent forwarding socket
  at `/run/host-services/ssh-auth.sock`). OrbStack and Colima run the images, but
  neither provides that socket; SSH agent forwarding — and therefore `git push` over
  SSH inside the sandbox — will not work. On those engines `claude-docker-doctor` exits
  non-zero, and `claude-docker-configure` still prints the build command but will not
  offer to run it for you; build and run anyway, only git-over-SSH is affected. See
  [Known limitations](README.md#known-limitations).
- About **12 GB of free disk** before the first build — it refuses to start below that.
  See [Build cost](README.md#build-cost).
- `zsh`
- `jq`, `git` (plus `sed`, `awk`, `grep`, `shasum`, `column`, `du`, `df`, `mktemp` — all
  stock on macOS)
- Claude Code installed and signed in on the host (the build reads `~/.claude.json`).
  Note that the **sandbox does not inherit that login** — you sign in once more inside it
  on first run; see
  [You sign in to Claude Code again](README.md#you-sign-in-to-claude-code-again-inside-the-sandbox).
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

## Let an AI assistant do it

[SETUP-PROMPT.md](SETUP-PROMPT.md) is a prompt you can paste into Claude Code, Warp,
Codex, Cursor or any coding agent with shell access. It detects your plugin manager,
asks you the configuration questions, and tests the result — checking with you before it
changes anything. The sections below are that same install by hand.

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

zinit sources a specific file rather than resolving a plugin directory convention;
point it at the root shim:

```zsh
zinit light abossenbroek/tupperclaude
```

zinit's default `as"plugin"` mode already discovers `*.plugin.zsh` at a repo root, which
this repo has. Do **not** add `as"program"` — that treats the repo as a binary, puts its
directory on `$PATH` and never sources anything, leaving no command defined.

## antidote

Add to your plugins file (usually `~/.zsh_plugins.txt`):

```
abossenbroek/tupperclaude
```

If your `.zshrc` sources a generated `~/.zsh_plugins.zsh` rather than calling
`antidote load`, the line above loads nothing until you regenerate it:

```zsh
antidote bundle < ~/.zsh_plugins.txt > ~/.zsh_plugins.zsh
```

## sheldon

```zsh
sheldon add tupperclaude --github abossenbroek/tupperclaude
```

A fresh sheldon install also needs this line in `~/.zshrc`, or nothing it manages
loads at all:

```zsh
eval "$(sheldon source)"
```

## antigen

```zsh
antigen bundle abossenbroek/tupperclaude
```

The bundle line has to come **above** your `antigen apply`; a bundle declared after
it is ignored.

## zplug

```zsh
zplug "abossenbroek/tupperclaude", use:"tupperclaude.plugin.zsh"
zplug install
```

Same ordering rule: the line goes **above** `zplug load`. `zplug install` is what
actually clones it — without that, the next shell reports the plugin as not
installed.

## Manual (no plugin manager)

```zsh
git clone https://github.com/abossenbroek/tupperclaude ~/.tupperclaude
echo 'source ~/.tupperclaude/tupperclaude.plugin.zsh' >> ~/.zshrc
exec zsh
```

## After installing

```zsh
claude-docker-configure   # interactive setup — recommended first step
claude-docker-build-arm   # first build (Apple Silicon; claude-docker-build-amd64 on Intel)
claude-docker-doctor      # verify everything, now that the image exists
claude-docker-arm
```

`claude-docker-configure` offers to run the build for you at the end; you may not need
to type it. It regenerates `~/.tupperclaude.zsh` from the template, so any option it
does not ask about — `docker-sock`, `home`, `dockerfile`, `machine-md` — reverts to its
default. `docker-sock` is the one worth watching: it defaults to **on**, which is
equivalent to root on the host. It takes a timestamped backup first, so re-adding a
dropped line is a copy-paste.

Run `claude-docker-doctor` **after** the build, not before: it treats the base image for
your architecture as a required check, which means on a machine that has not built yet it
reports a `FAIL` for it and exits non-zero — correct behaviour, but an alarming first
command.

The first build takes roughly 15 minutes, wants about 12 GB free to start, and produces a
~9 GB image — see [Build cost](README.md#build-cost). It asks for confirmation the first
time; `-y`/`--yes` skips that. On first launch you sign in to Claude Code again inside the
sandbox, which keeps its own credentials — see
[the README](README.md#you-sign-in-to-claude-code-again-inside-the-sandbox).

`tupperclaude` (bare) prints the version and the full command table. Every
`claude-docker-*` command, `claude-ts-ensure` and `tupperclaude` itself take
`-h`/`--help`; on the run commands that help belongs to the wrapper; use
`claude-docker-arm -- --help` to reach `claude`'s own.

See [README.md](README.md) for the full command table and configuration reference, and
[Getting started](README.md#getting-started) for the shortest path that needs no
Tailscale account.

## Running the tests

The zsh implementation has a suite that needs no Docker daemon:

```zsh
zsh zsh/tests/run-tests.zsh
```

It also runs in CI on every push and pull request. Run it before and after any patch.

## Uninstall

1. Remove the plugin line:
   - **oh-my-zsh:** delete `tupperclaude` from `plugins=(...)` in `~/.zshrc`, then
     `rm -rf ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/tupperclaude`
   - **zinit:** `zinit delete abossenbroek/tupperclaude`
   - **antidote:** remove the `abossenbroek/tupperclaude` line from your plugins file,
     then regenerate the bundle if your setup uses a static one
   - **sheldon:** `sheldon remove tupperclaude`
   - **antigen / zplug:** remove the `bundle`/`zplug` line and remove the cached clone
     per your manager's own cache-clear command
   - **manual:** remove the `source` line from `~/.zshrc` and `rm -rf ~/.tupperclaude`
2. Remove the generated configuration file **and** the line that sources it:

   ```zsh
   rm -f ~/.tupperclaude.zsh ~/.tupperclaude.zsh.bak-*
   ```

   If you installed with [SETUP-PROMPT.md](SETUP-PROMPT.md), it also left a backup of
   your zshrc per run: `rm -f ~/.zshrc.tupperclaude-bak-*` (or the same name under
   `$ZDOTDIR`).

   Then delete `source ~/.tupperclaude.zsh` from `~/.zshrc`. If you leave that line
   behind with the file gone, every new shell prints an error. (The file is written by
   `claude-docker-configure`; see
   [Configuration file](README.md#configuration-file).)

3. Remove containers, sidecars, volumes, images and state:

   ```zsh
   claude-docker-clean --state
   ```

   Read the plan it prints before confirming — besides containers and volumes it removes
   all four `claude-code-full-*` image tags, each a ~15 minute rebuild natively (much
   longer for an `amd64` image cross-built on Apple Silicon). `--state` is what removes
   the per-directory state under `~/.config/claude-docker*/instances` — or the equivalent
   under your `home` override; nothing removes it otherwise. It does **not** remove the
   sandbox's Claude credentials; delete
   `~/.config/claude-docker*/.credentials.json` yourself if you want those gone. Or do it
   manually:

   ```zsh
   docker rm -f $(docker ps -aq --filter label=tupperclaude.dir) 2>/dev/null
   docker ps -a --filter name=claude-ts- -q | xargs -r docker rm -f
   docker rmi claude-code-full-arm64 claude-code-full-amd64 \
              claude-code-full-playwright-arm64 claude-code-full-playwright-amd64
   docker volume ls -q --filter 'name=^claude-ts-' | xargs -r docker volume rm
   rm -rf ~/.config/claude-docker ~/.config/claude-docker-playwright
   ```

   The last line assumes the default state root; with a `home` override, remove your own
   path and its `-playwright` sibling instead (`claude-docker-doctor` prints the resolved
   one).

4. Verify nothing was missed — **both** of these should print nothing:

   ```zsh
   docker ps -a --filter label=tupperclaude.dir --format '{{.Names}}'   # sandboxes
   docker ps -a --filter name=claude-ts- --format '{{.Names}}'          # sidecars
   ```

   They must be two separate commands. Docker ANDs filters of different keys, and sidecars
   carry no `tupperclaude.dir` label — combining them into one command therefore always prints
   nothing and would give you a false all-clear.

# tupperclaude

An oh-my-zsh plugin that runs [Claude Code](https://claude.com/claude-code) inside a
sandboxed Docker container with a full development toolchain, arch-native images for
both Apple Silicon and Intel, and an optional per-directory
[Tailscale](https://tailscale.com) sidecar for networking.

**macOS only**, and built against **Docker Desktop** — see
[Requirements](INSTALL.md#requirements). **Prerelease: version `0.1.0-dev`.** Interfaces
and command names may still change between commits.

Your working directory is bind-mounted at the same absolute path, so edits are live on
both sides. Everything else — installed packages, stray processes, `rm -rf` accidents —
stays in the container.

**A note on names.** The project is *tupperclaude*, but the commands, paths and
environment variables are spelled `claude-docker` / `CLAUDE_DOCKER_*` (the plugin grew
out of a script by that name). Both refer to the same thing; only `tupperclaude` itself,
the container labels and the message prefix use the project name.

A fish sibling is planned; see [`fish/README.md`](fish/README.md).

## Install

See [INSTALL.md](INSTALL.md) for oh-my-zsh, zinit, antigen, zplug, and manual setup.

## Getting started

The fastest correct route, for a machine that has Docker Desktop and **no Tailscale
account**:

```zsh
zstyle ':omz:plugins:tupperclaude' network default   # skip Tailscale entirely
claude-docker-build-arm                              # ~15 min, one time (see Build cost)
claude-docker-doctor                                 # confirm everything is in place
cd ~/some/project
claude-docker-arm
```

The build comes **before** `claude-docker-doctor` on purpose: doctor treats the base
image for your own architecture as a *required* check, so run before the build it prints
a `FAIL` row for it and exits non-zero. That is doctor working correctly, not a broken
install — but it makes a poor first impression when it is the first command you type.

`zstyle` typed at a prompt applies to **that shell only**. It gets you through the lines
above; put it in `~/.tupperclaude.zsh` (or `~/.zshrc`) before you open a second terminal,
or the next shell falls back to the `tailscale` default and fails with
`tupperclaude: error: no auth key configured`. See
[Configuration file](#configuration-file).

`network` defaults to **`tailscale`**, which needs a Tailscale account and an auth key
before a sandbox can come up at all. `network default` uses plain Docker bridge
networking and needs neither. You can switch later without rebuilding — it is a run-time
option. See [`network`](#network) and [Networking](#networking).

`claude-docker-configure` walks through the same decisions interactively and writes them
to `~/.tupperclaude.zsh`; see [Configuration file](#configuration-file).

### You sign in to Claude Code again, inside the sandbox

The sandbox does **not** inherit your host Claude Code login, and this surprises people
on their first run. The build bakes in your non-secret config but never your credentials,
and the run path does not copy them either: it creates an empty
`<state root>/.credentials.json` on the host and mounts *that* at
`/home/agent/.claude/.credentials.json`. Your own `~/.claude/.credentials.json` is never
read.

So the first `claude-docker-arm` lands you in tmux at Claude Code's sign-in prompt. Sign
in there as usual. After that:

- the credentials live in `~/.config/claude-docker/.credentials.json` (or the equivalent
  under your [`home`](#home) override) and are **shared by every sandbox using that state
  root**, in every directory — you sign in once, not once per project;
- the Playwright variant has its own state root and therefore its own credentials file,
  so it asks once too;
- `claude-docker-clean` never removes either file, so rebuilding an image does not cost
  you the login. To clear it deliberately, delete the file.

### Build cost

The first build is expensive: it compiles and installs a Rust toolchain
(`rustc`/`cargo`/`rust-analyzer`), a full LSP stack, and every other tool in the list
below. Budget roughly **15 minutes** on Apple Silicon, and roughly **9 GB** of disk for
the base image — about **11 GB** for the Playwright variant, which is built on top of it
and shares its layers. Later builds reuse cached layers and are far quicker unless you
change an early layer of the Dockerfile.

**You need about 12 GB free before it will start.** The finished sizes above are not the
requirement — intermediate layers are. The build measures free space on Docker's root
directory (falling back to `$HOME`, which is where Docker Desktop's disk image lives) and
**refuses to start** below ~12 GB, rather than failing twelve minutes in with Docker's
own `no space left on device`.

Because a build costs as much as `claude-docker-clean` refunds, a **first** build asks
before starting:

```
tupperclaude: claude-code-full-arm64 does not exist yet — building it takes ~15 minutes and ~9 GB of disk.
Continue? [y/N]
```

Pass **`-y` / `--yes`** to skip that prompt. A rebuild — the image already exists — never
asks. Without a terminal (CI, `… | tail`, the configure wizard) there is no prompt
either: the same cost is printed as a warning and the build proceeds. Those two flags are
all the build commands take; `docker build` flags such as `--no-cache` are **not**
forwarded, and passing one is an error rather than a silently ignored argument.

Cross-building `amd64` on Apple Silicon is a different order of magnitude — see
[Known limitations](#known-limitations).

## Commands

`tupperclaude` is the discoverable entry point: run it bare for the version and the full
command table.

| Command | What it does |
| --- | --- |
| `tupperclaude` | Print the version and the command table |
| `tupperclaude --version` | Print the version only |
| `tupperclaude build arm64\|amd64 [--playwright]` | Shorthand for the build commands below |
| `tupperclaude run arm64\|amd64 [--playwright] [claude args...]` | Shorthand for the run commands below |
| `tupperclaude doctor\|configure\|status\|shell\|clean` | Shorthand for the utility commands below |
| `claude-docker-configure` | Interactive wizard; writes `~/.tupperclaude.zsh` |
| `claude-docker-doctor` | Run every preflight check and print a pass/fail table with fixes |
| `claude-docker-status` | List running tupperclaude sandboxes and Tailscale sidecars |
| `claude-docker-clean` | Tear down containers, sidecars, volumes **and image tags** — see [Cleaning up](#cleaning-up) |
| `claude-docker-shell [cmd...]` | Open a shell in this directory's running container without disturbing its tmux session; with arguments, run them there instead |
| `claude-docker-build-arm [-y]` | Build the `linux/arm64` image (native on Apple Silicon) |
| `claude-docker-arm` | Run Claude Code in the arm64 container |
| `claude-docker-build-arm-playwright [-y]` | Build the `linux/arm64` Playwright variant |
| `claude-docker-arm-playwright` | Run Claude Code in the arm64 Playwright container |
| `claude-docker-build-amd64 [-y]` | Build the `linux/amd64` image (native on Intel Macs, QEMU cross-build on Apple Silicon — see [Known limitations](#known-limitations)) |
| `claude-docker-amd64` | Run Claude Code in the amd64 container |
| `claude-docker-build-amd64-playwright [-y]` | Build the `linux/amd64` Playwright variant |
| `claude-docker-amd64-playwright` | Run Claude Code in the amd64 Playwright container |
| `claude-ts-ensure` | (plumbing) Bring up / repair the Tailscale sidecar |

The dispatcher takes `arm64` or `amd64` (and tolerates the bare `arm` / `amd` spellings,
so nothing you read off the screen is rejected). Everywhere else — the image tags, the
`linux/arm64` platform, doctor's table — the spelling is `arm64`; only the command names
themselves say `arm`.

Every `claude-docker-*` command and `tupperclaude` itself takes **`-h` / `--help`**;
`tupperclaude` and `claude-docker-doctor` also take `--version`. On the run commands
`--help` belongs to the wrapper; use `claude-docker-arm -- --help` to pass `--help`
through to `claude`. Any other extra arguments to a run command pass straight through to
`claude`.

**Shell completion** ships in `zsh/completions/` and is registered by adding that
directory to `$fpath` at plugin-load time. oh-my-zsh users get it automatically, since
oh-my-zsh runs `compinit` after plugins load. If you load the plugin by hand, make sure
your own `compinit` call comes *after* the `source` line.

The Playwright variant builds **on top of** the matching base image (same arch), so
build the base image first. It adds `--ipc=host` at run time, which Playwright's own
docs recommend for Chromium — the base image's `tini` entrypoint already handles zombie
reaping, so no extra `--init` flag is needed. It also uses its own state root and its own
Tailscale node (sidecar prefix `claude-ts-pw-`), so a Playwright sandbox and a base
sandbox can run in the same directory without colliding.

## Usage

```zsh
cd ~/some/project
claude-docker-configure     # first time only
claude-docker-build-arm     # first time only, or after upgrading the Dockerfile
claude-docker-arm
```

You land in a `tmux` session with:

| Window | Purpose |
| --- | --- |
| `claude` | Claude Code itself |
| `adc` | A shell with the `gcloud` ADC login command **pre-typed but not executed** — one Enter away when a token expires |
| `net` | *(tailscale network mode only)* A tailnet liveness probe; a silent disconnect rings the terminal bell instead of surfacing as mystery tool failures |

On first run in a directory, a `MACHINE.md` is written **into your working directory**
describing the environment to Claude — image, architecture, variant, network mode,
mounts, and the toolchain. Since it lands in your git working tree, add it to
`.gitignore` (or delete it — nothing depends on it):

```zsh
echo 'MACHINE.md' >> .gitignore
```

It is **refreshed, not just created.** The first line is a marker recording which image,
variant and network mode wrote the file; when any of those differs the file is rewritten.
That is deliberate: without it, switching a directory from the base variant to the
Playwright one would leave a stale `MACHINE.md` telling Claude it has no browser. The
cost is that **your own edits to a tupperclaude-written `MACHINE.md` are lost** the next
time you switch variant, arch or network mode.

Ownership is decided by that marker line alone: a `MACHINE.md` containing no
`<!-- tupperclaude: … -->` line is somebody's own document and is never touched, however
much it may talk about tupperclaude. Set [`machine-md`](#machine-md) to `off` to stop
writing the file at all.

Run `versions` inside the container for the full toolchain list with version numbers.
Toolchain: claude, gh, gcloud, tailscale (CLI only), docker (host socket), git,
node/npm/pnpm/yarn/bun, python3/uv, php/composer, rustc/cargo/rustfmt/clippy/rust-analyzer,
deno, linear-cli, pulumi, mise, psql, mysql, tmux, ripgrep, jq, yq, clang/clangd/cmake,
pyright, typescript-language-server, svelte-language-server/svelte-check, and optionally
aws.

## Differences from stock Claude Code

The sandbox is not a byte-identical Claude Code environment. The deliberate differences:

- **Agent teams are on.** The image sets `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`, and
  the launcher starts `claude --teammate-mode in-process`. Teammates therefore run in the
  same process rather than as separate sessions.
- **Worktrees are shared with the host.** `$HOME/.claude/worktrees` is bind-mounted at
  the same path inside the container, so worktrees created in one are visible in the
  other.
- **mise configs in the working directory are pre-trusted.** `MISE_TRUSTED_CONFIG_PATHS`
  is set to `$PWD/mise.toml:$PWD/.mise.toml:$PWD/.mise/config.toml`, so `mise` never
  prompts for trust inside the sandbox. It covers the working directory only.
- **Teams/tasks/projects state is per-directory**, not global — see
  [How it works](#how-it-works).
- **You sign in again inside the sandbox**, against a credentials file that is not your
  host one — see [above](#you-sign-in-to-claude-code-again-inside-the-sandbox).
- **Permission prompts behave normally through the `claude-docker-*` commands, but the
  image's own default does not.** The image inherits
  `CMD ["claude","--dangerously-skip-permissions"]` from the Docker-published base image.
  Every run command **overrides** that command line, so a tupperclaude sandbox starts
  `claude --teammate-mode in-process` and prompts as usual. Anyone who runs
  `docker run claude-code-full-arm64` by hand, with no command of their own, gets the
  permission bypass instead.

## Configuration

Options are read at **call time**, via
`zstyle ':omz:plugins:tupperclaude' <key> <value>` with a `CLAUDE_DOCKER_*` environment
variable fallback and a hard-coded default. Because they're resolved at call time, not
plugin-load time, `zstyle` lines work anywhere in `.zshrc` — before or after
`plugins=(...)`, before or after `source $ZSH/oh-my-zsh.sh`. The `zstyle` layer has no
load-order requirement of its own.

### Configuration file

`claude-docker-configure` writes **`~/.tupperclaude.zsh`** and offers to add
`source ~/.tupperclaude.zsh` to your `~/.zshrc`. That file is the recommended place for
your overrides:

- It is **generated** from `zsh/templates/tupperclaude.zsh`, and **fully regenerable** —
  re-run `claude-docker-configure` at any time. The previous version is backed up
  alongside it as `~/.tupperclaude.zsh.bak-<timestamp>` first.
- It is plain zsh containing the `zstyle` lines documented below, with every option
  present as a commented example. Editing it by hand is fine; a later
  `claude-docker-configure` run replaces it (after backing it up).
- Nothing else writes it, and nothing reads it except your `~/.zshrc`.

**Uninstalling means removing both halves:** delete `~/.tupperclaude.zsh` *and* the
`source ~/.tupperclaude.zsh` line from `~/.zshrc`. Leaving the line behind with the file
gone makes every new shell print an error.

`$ZSH_CUSTOM/tupperclaude.zsh` also works for oh-my-zsh users (anything in `$ZSH_CUSTOM`
is auto-sourced), as does putting the `zstyle` lines directly in `~/.zshrc`.

### `network`

- **zstyle:** `zstyle ':omz:plugins:tupperclaude' network <tailscale|default>`
- **env var:** `CLAUDE_DOCKER_NETWORK`
- **default:** `tailscale`
- **valid values:** `tailscale`, `default`

`default` uses plain Docker bridge networking — **no Tailscale account needed at all**.
Start here if you just want a sandbox. `tailscale` gives the container full tailnet
access through a per-directory sidecar; see [Networking](#networking) below and
[Supplying the Tailscale auth key](#supplying-the-tailscale-auth-key).

```zsh
zstyle ':omz:plugins:tupperclaude' network default
```

### `op-ref`

- **zstyle:** `zstyle ':omz:plugins:tupperclaude' op-ref <op://vault/item/field>`
- **env var:** `CLAUDE_DOCKER_OP_TS_REF`
- **default:** *(unset)*

A 1Password secret reference for the Tailscale auth key. Only consulted when `network`
is `tailscale` and `TS_AUTHKEY` is not set. See
[Supplying the Tailscale auth key](#supplying-the-tailscale-auth-key).

```zsh
export CLAUDE_DOCKER_OP_TS_REF='op://Private/Tailscale/authkey'
```

### `aws`

- **zstyle:** `zstyle ':omz:plugins:tupperclaude' aws <on|off>` (boolean: `zstyle -t`
  semantics, so `true`/`yes`/`on`/`1` are all true; `claude-docker-configure` writes
  `aws 'on'`)
- **env var:** `CLAUDE_DOCKER_INCLUDE_AWS`
- **default:** off
- **read at:** build time

Includes AWS CLI v2 in the image. Off by default to keep the image smaller.

```zsh
export CLAUDE_DOCKER_INCLUDE_AWS=1
claude-docker-build-arm
```

At run time `~/.aws` is mounted read-only and copied into the container, so your
existing profiles and SSO config work regardless of this option.

### `home`

- **zstyle:** `zstyle ':omz:plugins:tupperclaude' home <path>`
- **env var:** `CLAUDE_DOCKER_HOME`
- **default:** `~/.config/claude-docker`

Host state root: per-directory instance state, the shared cargo cache, and the Claude
credentials file. The Playwright variant always uses this path with a `-playwright`
suffix (e.g. `~/.config/claude-docker-playwright`), so overriding `home` relocates both
trees together and they can never collapse onto each other. It applies to the
`network=tailscale` path too — the sidecar's generated `resolv.conf` is written under
this root.

Write the path unquoted, or the `~` stays literal:

```zsh
zstyle ':omz:plugins:tupperclaude' home ~/dockerstate/claude
```

### `dockerfile`

- **zstyle:** `zstyle ':omz:plugins:tupperclaude' dockerfile <path>`
- **env var:** `CLAUDE_DOCKER_DOCKERFILE`
- **default:** `<repo>/docker/Dockerfile` (or `docker/Dockerfile.playwright` for the
  Playwright variant)

Build from your own Dockerfile instead of the bundled one.

```zsh
zstyle ':omz:plugins:tupperclaude' dockerfile ~/my-claude-docker/Dockerfile
```

### `machine-md`

- **zstyle:** `zstyle ':omz:plugins:tupperclaude' machine-md <on|off>` (boolean:
  `zstyle -t` semantics)
- **env var:** `CLAUDE_DOCKER_MACHINE_MD`
- **default:** on

Whether to write `MACHINE.md` into the working directory at launch — see
[Usage](#usage) for what it contains and when it is refreshed. Turn it off if you would
rather a first run did not modify the repository you happen to be standing in; the
sandbox works the same, Claude just isn't told what kind of machine it is on.

```zsh
zstyle ':omz:plugins:tupperclaude' machine-md off
```

### `docker-sock`

- **zstyle:** `zstyle ':omz:plugins:tupperclaude' docker-sock <on|off>` (boolean:
  `zstyle -t` semantics)
- **env var:** `CLAUDE_DOCKER_DOCKER_SOCK`
- **default:** on

Whether to mount the host's `/var/run/docker.sock` into the container, which is what
lets Claude use `docker` inside the sandbox.

**Read this before leaving it on.** Access to the docker socket is equivalent to root
on the host: anything holding it can start a privileged container with your filesystem
mounted. So with this on — the default — the container is **not a security boundary**
against the code running inside it. A malicious dependency, or an agent that goes
wrong, can escape it.

It is on by default because that is the honest description of what this tool is: a
reproducible, disposable *environment*, whose isolation is about not polluting your
host, not about containing hostile code. Turning it off would also break every
workflow that builds or runs containers inside the sandbox, and `MACHINE.md` tells
Claude that `docker` is available.

Turn it off and you get a real boundary, at the cost of docker-in-the-sandbox:

```zsh
zstyle ':omz:plugins:tupperclaude' docker-sock off
```

Note this is about the *sandbox*, not the network: `--group-add 0` accompanies the
mount only so the container's user can read the socket, and widens nothing by itself.

### `TS_AUTHKEY`

Not a `zstyle` option — a plain environment variable, and the **highest-precedence**
source for the Tailscale auth key itself (checked before `op-ref`). See
[Supplying the Tailscale auth key](#supplying-the-tailscale-auth-key).

### API keys forwarded into the container

If set in your host shell, these are forwarded as-is (empty otherwise, no error):
`ANTHROPIC_API_KEY`, `LINEAR_API_KEY`, `GEMINI_API_KEY`, `OPENAI_API_KEY`,
`PULUMI_ACCESS_TOKEN`.

## Networking

**`network=default`** needs no Tailscale account: plain Docker bridge networking, ready
to go with zero setup.

**`network=tailscale`** gives each working directory its own persistent Tailscale
sidecar container (`claude-ts-<mangled-path>`, or `claude-ts-pw-<mangled-path>` for the
Playwright variant). The Claude container joins that sidecar's network namespace with
`--network=container:...`, so it inherits the tunnel without needing `NET_ADMIN` or
`/dev/net/tun` itself — the sidecar holds the privileges, the Claude container stays
unprivileged.

`claude-ts-ensure` runs before every launch **in `network=tailscale` mode** (in
`network=default` no sidecar exists and it is never called) and checks that the sidecar is
genuinely
*online*, not merely *running*: a sidecar that has lost its link to the coordination
server keeps its `100.x` address and still reports `BackendState=Running`, while a
container joining its netns silently gets a tailnet that resolves nothing. When that is
detected it restarts the sidecar, which re-establishes the netmap. The node identity
lives in a named volume, so this does not churn your Tailscale admin console.

If the tailnet degrades *during* a session, restarting the sidecar will not heal the
running container — its network namespace goes stale. Exit and relaunch; the launch path
repairs the sidecar.

### Supplying the Tailscale auth key

Only needed for `network=tailscale`. The sidecar needs a Tailscale auth key **once**,
when the node is first created. After that the node identity lives in a Docker named
volume and is reused, so the key is not read again unless you delete that volume.

Use a **reusable, tagged, ephemeral-off** key. Mint one at
<https://login.tailscale.com/admin/settings/keys>.

- **Reusable**, because you get one node per working directory — a single-use key
  authenticates the first one and then leaves every later directory failing to come up.
- **Tagged** (e.g. `tag:claude-docker`), so you can write ACLs that scope what these
  sandboxes can reach, and so the nodes don't expire against your user's key expiry.
- **Ephemeral off**, so a node keeps its identity across restarts instead of churning
  your admin console.

#### Option 1 — plain environment variable

Simplest. Export `TS_AUTHKEY` before the first run:

```zsh
TS_AUTHKEY='tskey-auth-...' claude-docker-arm
```

Prefer the one-shot form above over putting the key in `~/.zshrc`, where it lands in
plaintext on disk and leaks into the environment of every process you start.

#### Option 2 — 1Password (`op`)

Recommended if you already use 1Password. Nothing is written to disk, and the key is
only read at the moment the sidecar is created.

**Setup:**

1. Install the CLI and enable CLI integration:

   ```zsh
   brew install --cask 1password-cli
   ```

   Then in the 1Password desktop app: **Settings → Developer → Connect with 1Password
   CLI**. This lets `op` authenticate via Touch ID instead of a password prompt.

2. Store the key. Create an item (say, a Password item named `Tailscale` in your
   `Private` vault) with a field holding the auth key. To do it from the CLI:

   ```zsh
   op item create --category=password --title='Tailscale' --vault=Private \
     'authkey[password]=tskey-auth-...'
   ```

3. Copy its **secret reference** — the `op://vault/item/field` URI. Right-click the
   field in the app → *Copy Secret Reference*, or verify from the CLI:

   ```zsh
   op read 'op://Private/Tailscale/authkey'
   ```

4. Point the plugin at it in `~/.tupperclaude.zsh` (or `~/.zshrc`):

   ```zsh
   export CLAUDE_DOCKER_OP_TS_REF='op://Private/Tailscale/authkey'
   ```

The reference is not a secret, so it is safe in a dotfiles repo.

If the vault is locked or signed out, neither command misreports it as a missing key:
`claude-docker-doctor` fails its `op-signin` row with `op signin` as the fix, and
`claude-ts-ensure` refuses to create a sidecar that could never authenticate, pointing
you at `op read '<your ref>'` to show the underlying error.

#### Option 3 — another password manager

`TS_AUTHKEY` takes precedence over the 1Password path, so any manager with a CLI works
by exporting it. Wrap the run command in a shell function in `~/.zshrc`:

```zsh
# Bitwarden
cdk() { TS_AUTHKEY="$(bw get password 'Tailscale authkey')" claude-docker-arm "$@" }

# HashiCorp Vault
cdk() { TS_AUTHKEY="$(vault kv get -field=authkey secret/tailscale)" claude-docker-arm "$@" }

# pass (the standard unix password manager)
cdk() { TS_AUTHKEY="$(pass tailscale/authkey)" claude-docker-arm "$@" }

# macOS Keychain — store once, then read on demand
#   security add-generic-password -a "$USER" -s tailscale-authkey -w 'tskey-auth-...'
cdk() { TS_AUTHKEY="$(security find-generic-password -a "$USER" -s tailscale-authkey -w)" claude-docker-arm "$@" }
```

Since the key is only consumed when the sidecar node is first created, you can also skip
all of this and just paste it inline once, as in Option 1.

## How it works

**State.** Per-directory: `teams`, `tasks`, `projects` under
`$CLAUDE_DOCKER_HOME/instances/<mangled-path>/` (a separate tree per variant — see the
`home` option). Shared across every session using the same state root: the sandbox's
Claude credentials file and the cargo registry cache.

**The sandbox's Claude login.** `<state root>/.credentials.json` is created empty on
first run and mounted over `/home/agent/.claude/.credentials.json`. It is the sandbox's
own login, entirely separate from the host's — see
[above](#you-sign-in-to-claude-code-again-inside-the-sandbox).

**Host credentials.** Host credential stores (`~/.ssh`, `gh`, `gcloud`, Linear, Pulumi, `~/.aws`)
are mounted read-only at `/run/host-*` and copied to their real locations at container
startup, so the container can modify them freely without ever writing to your host
files. Only paths that actually exist are mounted — a bind mount of a missing path would
make Docker create a root-owned empty directory on the host, so tupperclaude checks
first. A Pulumi access token is derived from the credentials file when
`PULUMI_ACCESS_TOKEN` isn't already set, so both the CLI and the Pulumi MCP server
authenticate.

**SSH agent.** Docker Desktop for Mac synthesises the forwarded agent socket at
`/run/host-services/ssh-auth.sock`, which is mounted into the container so `git push`
over SSH works. Other engines do not provide it — see [Known limitations](#known-limitations).

**Git worktrees.** If the working directory is a git worktree, the main checkout is also
mounted at its own path so git can follow the `.git` file's gitdir pointer.

## Cleaning up

`claude-docker-clean` is the teardown command, and it is **more destructive than its name
suggests**. By default it:

- stops every running sandbox container carrying a `tupperclaude.arch` label;
- removes every `claude-ts-*` sidecar container — including ones that are **up and
  carrying a live session**, which dies with the sidecar's network namespace;
- removes the `claude-ts-state-*` and `claude-ts-sock-*` volumes;
- **removes all four image tags** (`claude-code-full-arm64`, `claude-code-full-amd64`,
  and their `-playwright` siblings) that exist locally. This is the expensive part: the
  command prices each rebuild at ~15 minutes, which is the native figure — an `amd64`
  image cross-built under QEMU on Apple Silicon takes far longer than that (see
  [Known limitations](#known-limitations)).

It does **not** remove per-directory state, and it never touches the Docker-only Claude
credentials at `~/.config/claude-docker*/.credentials.json` (or the equivalent under your
[`home`](#home) override) — so a teardown does not cost you the sandbox login.

It prints the full plan first — every container by directory, image tag with its size,
and volume — and asks for confirmation. Anything costly upgrades the prompt from a
keypress to typing `yes`: a live session that would be killed, state history that a
running sandbox is still using, or images totalling more than 1 GB — including images
whose size Docker did not report, which count as expensive rather than as free.

| Flag | Effect |
| --- | --- |
| `-n`, `--dry-run` | Print exactly what would be removed, then exit |
| `-y`, `--yes` | Skip the prompt. **Refused** in three cases (see below), unless `--force` is also given |
| `--force` | Permit `-y` in those cases |
| `--containers` | *Only* the containers: stop the labelled sandboxes, remove the `claude-ts-*` sidecars. This is the selector that can kill a session |
| `--images` | *Only* whichever of the four image tags exist locally |
| `--volumes` | *Only* the `claude-ts-*` state and socket volumes. Without `--containers`, only the **orphaned** ones — the rest are held open by sidecars that are staying, and Docker would refuse anyway |
| `--state` | *Also* remove per-directory state (`<state root>/instances`: teams, tasks, projects). Additive, never narrowing — and it arms the `--yes` refusal on its own whenever a sandbox is running, since that history has no rebuild path |
| `--prune` | *Also* run `docker image prune -f`, which removes **every** dangling image on the host, not just tupperclaude's |
| `-h`, `--help` | Usage (works without a Docker daemon) |

Give **no** selector and all three classes are removed, exactly as before selectors
existed. Give one or more and only those are touched — `claude-docker-clean --volumes`
reclaims orphaned volumes without going near tens of gigabytes of images or a single live
session. `--state` and `--prune` are not selectors: they stay additive opt-ins on top of
whatever the selectors chose.

`--yes` is refused — unless `--force` joins it — whenever any of these holds:

- a labelled **sandbox** is running and containers are in scope;
- a **sidecar** is running and containers are in scope;
- **`--state`** is given, there is state to remove, and any labelled sandbox is running —
  whether or not containers are in scope. A running sandbox has its state directory
  bind-mounted, and that history is the one thing here with no rebuild path.

Read none of that as a Tailscale-only safeguard. Under `network=default` there is no
sidecar at all, and the labelled sandboxes are then the only thing standing between
`--yes` and every live session on the machine. And because the third case ignores the
selectors, `claude-docker-clean --yes --images --state` **is** refused while a sandbox is
up, even though it stops no container: the images are a 15-minute rebuild, but a session's
task, team and project history is simply gone. `claude-docker-clean --yes --images` on its
own is never refused.

Per-directory state accumulates forever and nothing removes it by default — not the run
path, not `claude-docker-clean` without `--state`. Removing it also removes each
sandbox's own history, which is why it is opt-in.

`docker rmi` only touches the `:latest` tag, so any other tag you pushed onto the same
repository (a `pre-zsh-port` style backup, say) survives; `claude-docker-clean` lists
those as preserved rather than leaving you to discover them.

## Privacy note

The build bakes a whitelist of your **own** Claude Code config into the image:
`~/.claude.json`, `~/.claude/CLAUDE.md`, `settings.json`, `skills/`, `commands/`, and
plugin metadata. Your Claude credentials are *not* baked, and are not copied in at run
time either — the sandbox keeps its own login, which you create the first time you run it
(see [above](#you-sign-in-to-claude-code-again-inside-the-sandbox)).

`~/.claude.json` can still contain MCP server definitions with inline API keys. The build
warns when it spots key/token-shaped fields. **Treat the built image as private: do not
push `claude-code-full-*` to a shared or public registry.**

### API keys are visible in the process list

`ANTHROPIC_API_KEY`, `LINEAR_API_KEY`, `GEMINI_API_KEY`, `OPENAI_API_KEY` and
`PULUMI_ACCESS_TOKEN` are forwarded into the container as `-e NAME=value` arguments. That
is what makes them work inside the sandbox, but it also means their values appear in the
`docker run` command line — visible to anyone who can run `ps` on your machine, and to
`docker inspect` on the running container.

On a single-user laptop this is normally an acceptable trade. It is worth knowing about if
you share the machine, and worth remembering before pasting the output of `ps`, `docker
inspect`, or a debug log into an issue or a chat.

## Supply chain

`docker/Dockerfile` applies the same policy to every third-party component. It is the
strongest part of the supply chain, and it is not the whole of it: the Playwright variant
is weaker on purpose, and the Tailscale sidecar is not pinned at all — both are covered
below, and both are worth reading before you conclude the image is pinned end to end.

- the base image (`docker/sandbox-templates:claude-code`, published by Docker Inc.) is
  pinned to an **immutable multi-arch manifest digest**, not a floating tag
- an exact version is pinned via a Dockerfile `ARG` — never `latest`, never
  `releases/latest`
- the artifact is verified against a vendor-published `sha256` before it is used
- apt repositories are pinned to a vendor keyring (`signed-by=`)
- npm packages are pinned exactly and installed with `--ignore-scripts` **wherever the
  package permits it**, which blocks the most common npm supply-chain vector
- every `RUN` executes under `bash -o pipefail`, so a failed download in a pipeline fails
  the build instead of feeding an empty file to the next stage

Five deliberate exceptions, each documented again at its own layer:

1. **Claude Code** is neither version-pinned nor checksum-verified: it tracks the
   `latest` channel by design so the image matches a freshly upgraded host, and it is
   installed through the vendor's own `curl https://claude.ai/install.sh | bash`
   bootstrap — the one such pipe in the file.
2. **aws-cli** (optional) has no vendor-published checksum file; AWS publishes a GPG
   signature only. The `sha256` in the `ARG` was computed once from the pinned artifact
   and is verified on every build.
3. **linear-cli** is version-pinned, but has no checksum of ours: `deno install
   jsr:…@X.Y.Z` resolves module integrity against JSR's own per-version manifest, and
   there is no single artifact to hash.
4. **uv** is a `COPY --from` an immutable image digest rather than an `ARG` + `sha256`.
   That is stronger, not weaker — the digest covers the whole multi-arch manifest.
5. **bun** is the one npm package installed *without* `--ignore-scripts`
   (`npm install -g bun@1.3.14`): its postinstall is what fetches the platform binary, so
   suppressing lifecycle scripts would install nothing usable. The version is pinned
   exactly, but its install scripts do run. Every other global npm package —
   `typescript`, `typescript-language-server`, `pyright`, `svelte-language-server`,
   `svelte-check`, `pnpm`, `yarn` — is pinned *and* installed with `--ignore-scripts`.

Notably, `pulumi`, `rustup`, `deno`, and `mise` are installed from checksum-verified
release artifacts rather than the vendors' `curl ... | sh` bootstrap scripts, which
publish no checksum.

### The Tailscale sidecar is not covered by any of the above

All of that describes `docker/Dockerfile` — the image you run Claude in. In
`network=tailscale` mode tupperclaude also starts a **second, far more privileged**
container that no Dockerfile in this repo builds, and it is pinned to nothing:

- `claude-ts-ensure` runs **`tailscale/tailscale:latest`** — a floating tag, no digest,
  no checksum. Whatever that tag resolves to on the day the sidecar is first created is
  what runs, and `--restart unless-stopped` keeps it around afterwards.
- It runs with `--cap-add=net_admin --cap-add=net_raw --device=/dev/net/tun`, because
  kernel-mode networking needs them. The Claude container itself stays unprivileged and
  merely joins the sidecar's network namespace — the privileges are concentrated here, in
  the container you did not build.
- Your **Tailscale auth key is passed to it in its environment** (`-e TS_AUTHKEY=…`), so
  it is visible to `docker inspect` on that container. See also
  [API keys are visible in the process list](#api-keys-are-visible-in-the-process-list).

`network=default` starts **no sidecar at all**: no second container, no extra
capabilities, no `/dev/net/tun`, no auth key anywhere. That is the smaller attack surface
as well as the simpler setup.

### The Playwright variant is weaker, deliberately

`docker/Dockerfile.playwright` cannot hold the same line, which is why it is a separate
opt-in image rather than the default:

- `playwright install chromium` downloads a per-arch Chromium build from a revision
  embedded in the library. There is **no vendor-published checksum** for those builds and
  no supported way to hand Playwright a pre-verified binary, so the browser is downloaded
  and executed on TLS trust alone. This is the weakest link in the image.
- `npx --yes playwright@$PWVER` executes whatever the npm registry serves for that
  version. The version is exact, but no integrity hash of ours is checked.
- `$PWVER` is resolved live from `npm view @playwright/mcp@X dependencies.playwright`
  rather than hardcoded, so the MCP and the library stay in lockstep from one pinned
  source. The lookup is guarded, so an empty result fails the build instead of installing
  `playwright@`.

What *is* pinned: `@playwright/mcp` to an exact version (`ARG
PLAYWRIGHT_MCP_VERSION=0.0.79`, referenced by the dependency install, the browser install
and the `mcpServers` registration so the three cannot drift), the Playwright library
version derived from it, and the base image via `BASE_IMAGE`. As in the base image, npm
installs here use `--ignore-scripts` where the package permits it — `playwright install
chromium` is not an npm lifecycle script at all, and is run explicitly afterwards.

### Updating pinned versions

Bump the `ARG` in `docker/Dockerfile` and take the new checksum from the vendor's own
published checksum file:

| Component | Where the checksum comes from |
| --- | --- |
| base image | `docker buildx imagetools inspect docker/sandbox-templates:claude-code` — take the top-level index digest (it must list both `linux/amd64` and `linux/arm64`) |
| composer | download `https://getcomposer.org/download/<ver>/composer.phar` and record `shasum -a 256` of it as `COMPOSER_SHA256`. Deliberately hardcoded rather than fetched at build time: the same origin serves the phar and any hash that would check it, so a compromised origin would pass its own check |
| yq | `https://github.com/mikefarah/yq/releases/download/<ver>/checksums` — SHA-256 is column 19 (see the `checksums_hashes_order` file) |
| tailscale | `https://pkgs.tailscale.com/stable/tailscale_<ver>_<arch>.tgz.sha256` |
| pulumi | `https://github.com/pulumi/pulumi/releases/download/v<ver>/pulumi-<ver>-checksums.txt` |
| rustup | `https://static.rust-lang.org/rustup/archive/<ver>/<target>/rustup-init.sha256` |
| deno | `https://github.com/denoland/deno/releases/download/<ver>/deno-<target>.zip.sha256sum` |
| mise | `https://github.com/jdx/mise/releases/download/<ver>/SHASUMS256.txt` |
| uv | `docker manifest inspect ghcr.io/astral-sh/uv:<ver>` for the manifest-list digest |
| aws-cli | AWS publishes a GPG signature but no checksum file. Download `awscli-exe-linux-<slug>-<ver>.zip`, verify the `.sig` against AWS's published public key if you want the strongest guarantee, then record `shasum -a 256` of the zip. |

## Known limitations

- **`claude-docker-build-amd64` on Apple Silicon is untested end to end.** It works
  mechanically — `docker build --platform linux/amd64` cross-builds under QEMU — but a
  full toolchain build under emulation is prohibitively slow (the Rust layer alone can
  take a very long time), and no one has sat through a full run to confirm the result.
  The **arm64 image has been built and verified.** If you're on Apple Silicon, use
  `claude-docker-arm`; reach for `amd64` only if you specifically need x86_64 and are
  prepared for a long, unverified build.

- **A non-Docker-Desktop engine mostly works, but loses SSH agent forwarding — and the
  tooling is more alarmed about it than it needs to be.** OrbStack and Colima run the
  images fine, but neither synthesises `/run/host-services/ssh-auth.sock`, so `git push`
  over SSH inside the sandbox fails. Nothing else is affected. But `ssh-agent` is a
  **required** check, so on those engines:

  - `claude-docker-doctor` prints a `FAIL` row for it and **exits non-zero**, however
    healthy the rest of your setup is;
  - `claude-docker-configure` counts it among its failed prerequisites, so instead of
    offering to run the build for you it prints *"Prerequisites are not satisfied yet —
    fix the FAIL lines above, then:"* followed by `claude-docker-doctor` and the right
    build command for your architecture. You still get the command; what you lose is the
    wizard's *"Run it now? [y/N]"*.

  **Proceed anyway.** Run that build command yourself; the build and the sandbox work.
  Only git-over-SSH from inside the sandbox is broken, and HTTPS remotes (or `gh`, whose
  credentials are copied in) are unaffected.
  `network=tailscale` additionally needs `/dev/net/tun` in the engine's VM, which is
  likewise only verified against Docker Desktop.

- **`@playwright/mcp` is pinned to exactly 0.0.79, and 0.0.79 is a floor you cannot go
  below rather than a version anyone preferred.** The base image tracks Ubuntu 26.04,
  which no published Playwright yet lists in its browser-support allowlist, so
  `playwright install chromium` refuses with *"Playwright does not support chromium on
  ubuntu26.04-arm64"*. The image sets `PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS=1` to
  bypass that check — but Playwright releases before roughly 1.62 **ignore that variable
  entirely**, so the previous pin (0.0.75, which resolves to playwright 1.61.0-alpha)
  fails no matter what it is set to. Bumping the pin upward is fine; going below 0.0.79
  cannot work until Playwright adds Ubuntu 26.04, at which point the environment variable
  can be dropped instead. This is an allowlist gap, not a real incompatibility: the
  browser launches and renders correctly on `ubuntu26.04-arm64`, which the
  `claude-code-full-playwright-arm64` build has been verified end to end to do. No exact
  Chromium build number is quoted here: it is whatever revision the pinned Playwright
  library resolves to, and the two places that named one — this README and a comment in
  `docker/Dockerfile.playwright` — disagreed, so both were untrustworthy.

## Troubleshooting

Each heading is the literal text the command prints.

**`tupperclaude: error: no auth key configured`** — `network=tailscale` and no
`TS_AUTHKEY` or `op-ref`, with no existing sidecar to reuse. Supply a key (see
[Supplying the Tailscale auth key](#supplying-the-tailscale-auth-key)) or switch to
`zstyle ':omz:plugins:tupperclaude' network default`.

**`tupperclaude: error: claude-code-full-arm64 not built`** — (or any of the other three
image names) the image does not exist locally. Run the build command named in the fix
line underneath; for a `-playwright` image the base image of the same arch must exist
first. See [Build cost](#build-cost).

**`tupperclaude: error: a sandbox is already running for <dir> …`** — the line goes on to
name the arch, the variant and the container. One container per
directory and variant, so a second `claude-docker-arm` in the same directory would
collide on the container name. This is the ordinary second-terminal case. Nothing has
been changed and the live session is untouched: use `claude-docker-shell` for another
shell in it, or `docker attach <container>` to rejoin its tmux session. To run a *second*
Claude in the same repository, use a git worktree in a different directory.

**`tupperclaude: error: not enough free disk to build …: N GB free on <path>, ~12 GB
needed`** — the build refuses to start rather than fail deep in a layer. The fixes it
prints are `claude-docker-clean --dry-run` (what tupperclaude is holding, priced),
`docker system df` (what Docker is holding overall) and `docker builder prune` (drop the
build cache). Under Docker Desktop the path measured is your `$HOME`, since Docker's own
root lives inside the VM's disk image on that volume.

**`tupperclaude: error: Tailscale sidecar '<node>' did not come online within 45s.`** —
the command prints Tailscale's own health messages beneath it. Check
`docker logs claude-ts-<...>`. A key that was single-use and already consumed, or an
expired key, is the usual cause.

**`tupperclaude: error: no sandbox is running for <dir>`** — `claude-docker-shell` only
attaches to a sandbox already running for the *current* directory. Start one with
`claude-docker-arm`, or run `claude-docker-status` to see what is running elsewhere.

**`tupperclaude: error: unknown network mode '<mode>' (expected tailscale or default)`** —
a typo in the `network` zstyle or `CLAUDE_DOCKER_NETWORK`. Only `tailscale` and `default`
are valid.

**`engine is '<name>', not Docker Desktop`** — in the `ssh-agent` row of
`claude-docker-doctor`. You are on OrbStack, Colima or another engine; everything except
SSH agent forwarding still works. See [Known limitations](#known-limitations).

**`tupperclaude: error: claude-docker-configure needs an interactive terminal`** — the
wizard reads answers from the terminal, so it cannot run from a pipe, a script or CI.
Run it directly, or set the `zstyle` options by hand — [Configuration](#configuration)
documents each one, and the same list ships as commented examples in
`zsh/templates/tupperclaude.zsh` inside the plugin clone (where that clone lives depends
on your plugin manager; see [INSTALL.md](INSTALL.md)).

**`tupperclaude: error: claude-docker-clean needs an interactive terminal to confirm`** —
same cause. Use `claude-docker-clean --dry-run` to see the plan, or `--yes` to confirm up
front.

**`tupperclaude: error: refusing --yes: …`** — the rest of that line is assembled from
what is actually at risk, naming the sandboxes by working directory and the sidecars by
container name, so it is not a fixed sentence. Exit those sessions, narrow the sweep
(`claude-docker-clean --volumes` touches no container), or add `--force`. It fires on
running **sandboxes** as well as sidecars — so `network=default` users, who have no
sidecars at all, get it too — and on `--state` while a running sandbox has that state
bind-mounted, even when no container is being removed. See [Cleaning up](#cleaning-up).

**`tupperclaude: error: ~/.claude.json not found`** — you have never run Claude Code on
this host, and the build bakes that file into the image. Run `claude` on the host once
(signing in there as well), then build. Note that signing in on the host does *not* sign
you in inside the sandbox — see
[above](#you-sign-in-to-claude-code-again-inside-the-sandbox).

**`tupperclaude: error: ~/.claude.json is not valid JSON`** — the host config is corrupt;
fix it before building, since it gets baked into the image. `jq . ~/.claude.json` shows
where.

**Tools inside the container can't reach anything, but `tailscale status` looks fine** —
that's the stale-netmap case described in [Networking](#networking). Exit Claude and
relaunch.

**The amd64 build seems to hang on Apple Silicon** — it isn't hung, it's QEMU. See
[Known limitations](#known-limitations). Build arm64 unless you specifically need an
x86_64 image.

**Something else, or you're not sure where a failure is coming from** — run
`claude-docker-doctor`. It runs every preflight check and prints a fix for each failing
one, then the resolved configuration — version, `network`, state root, `aws`,
`machine-md`, plus `op-ref` when one is set and `dockerfile` when it is overridden. The
whole output is a good bug report as it stands; you do not need to describe your
configuration separately.

## Hacking

The zsh implementation has a test suite that runs without a Docker daemon — it drives the
commands against a fake `docker` on `$PATH` and asserts on the recorded argv:

```zsh
zsh zsh/tests/run-tests.zsh
```

The same suite runs in CI on every push and pull request
([`.github/workflows/test.yml`](.github/workflows/test.yml)). Run it before and after any
patch.

## Uninstall

1. Remove the plugin from `plugins=(...)` in `~/.zshrc` and delete the clone (see
   [INSTALL.md](INSTALL.md) for the path, which depends on your plugin manager).
2. Remove the configuration file and its `source` line:

   ```zsh
   rm -f ~/.tupperclaude.zsh ~/.tupperclaude.zsh.bak-*
   ```

   Then delete the `source ~/.tupperclaude.zsh` line from `~/.zshrc` — left behind, it
   makes every new shell print an error.

3. Remove containers, sidecars, volumes, images and state:

   ```zsh
   claude-docker-clean --state    # --state is what removes per-directory state
   ```

   Read the plan it prints before confirming: it also removes all four image tags. Or do
   it manually:

   ```zsh
   docker rm -f $(docker ps -aq --filter label=tupperclaude.dir) 2>/dev/null
   docker ps -a --filter name=claude-ts- -q | xargs -r docker rm -f
   docker rmi claude-code-full-arm64 claude-code-full-amd64 \
              claude-code-full-playwright-arm64 claude-code-full-playwright-amd64
   docker volume ls -q --filter 'name=^claude-ts-' | xargs -r docker volume rm
   rm -rf ~/.config/claude-docker ~/.config/claude-docker-playwright
   ```

   That last line assumes the default state root. If you set [`home`](#home), remove your
   own path and its `-playwright` sibling instead — `claude-docker-doctor` prints the
   resolved state root.

4. Verify nothing was missed:

   ```zsh
   docker ps -a --filter label=tupperclaude.dir --format '{{.Names}}'   # sandboxes
   docker ps -a --filter name=claude-ts- --format '{{.Names}}'          # sidecars
   ```

   An empty result from both means it's fully removed.

## License

Dual-licensed under your choice of the MIT License ([LICENSE-MIT](LICENSE-MIT)) or the
BSD 3-Clause License ([LICENSE-BSD](LICENSE-BSD)). SPDX identifier: `MIT OR BSD-3-Clause`.

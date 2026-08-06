# tupperclaude

An oh-my-zsh plugin that runs [Claude Code](https://claude.com/claude-code) inside a
sandboxed Docker container with a full development toolchain, arch-native images for
both Apple Silicon and Intel, and a per-directory [Tailscale](https://tailscale.com)
sidecar for networking (optional — see [Networking](#networking)).

Your working directory is bind-mounted at the same absolute path, so edits are live on
both sides. Everything else — installed packages, stray processes, `rm -rf` accidents —
stays in the container.

A fish sibling is planned; see [`fish/README.md`](fish/README.md).

## Install

See [INSTALL.md](INSTALL.md) for oh-my-zsh, zinit, antigen, zplug, and manual setup.

## Commands

| Command | What it does |
| --- | --- |
| `claude-docker-configure` | Interactive wizard to set up config — **start here** |
| `claude-docker-doctor` | Run every preflight check and print a pass/fail table with fixes |
| `claude-docker-status` | List running tupperclaude containers and sidecars |
| `claude-docker-clean` | Remove containers, sidecars, and per-directory state |
| `claude-docker-shell` | Open a shell in a running container without launching `claude` |
| `claude-docker-arm-build` | Build the `linux/arm64` image (native on Apple Silicon) |
| `claude-docker-arm` | Run Claude Code in the arm64 container |
| `claude-docker-arm-playwright-build` | Build the `linux/arm64` Playwright variant |
| `claude-docker-arm-playwright` | Run Claude Code in the arm64 Playwright container |
| `claude-docker-amd64-build` | Build the `linux/amd64` image (native on Intel Macs, QEMU cross-build on Apple Silicon — see [Known limitations](#known-limitations)) |
| `claude-docker-amd64` | Run Claude Code in the amd64 container |
| `claude-docker-amd64-playwright-build` | Build the `linux/amd64` Playwright variant |
| `claude-docker-amd64-playwright` | Run Claude Code in the amd64 Playwright container |
| `claude-ts-ensure` | (internal) Bring up / repair the Tailscale sidecar |

Any extra arguments to a run command pass straight through to `claude`.

The Playwright variant builds **on top of** the matching base image (same arch), so
build the base image first. It adds `--ipc=host` at run time, which Playwright's own
docs recommend for Chromium — the base image's `tini` entrypoint already handles
zombie reaping, so no extra `--init` flag is needed.

## Usage

```zsh
cd ~/some/project
claude-docker-configure     # first time only
claude-docker-arm-build     # first time only, or after upgrading the Dockerfile
claude-docker-arm
```

You land in a `tmux` session with:

| Window | Purpose |
| --- | --- |
| `claude` | Claude Code itself |
| `adc` | A shell with the `gcloud` ADC login command **pre-typed but not executed** — one Enter away when a token expires |
| `net` | *(tailscale network mode only)* A tailnet liveness probe; a silent disconnect rings the terminal bell instead of surfacing as mystery tool failures |

On first run in a directory, a `MACHINE.md` is written there describing the environment
to Claude. Delete it if you don't want it; it is only written when absent.

Run `versions` inside the container for the full toolchain list with version numbers.
Toolchain: claude, gh, gcloud, tailscale (CLI only), docker (host socket), git,
node/npm/pnpm/yarn/bun, python3/uv, php/composer, rustc/cargo/rustfmt/clippy/rust-analyzer,
deno, linear-cli, pulumi, mise, psql, mysql, tmux, ripgrep, jq, yq, clang/clangd/cmake,
pyright, typescript-language-server, svelte-language-server/svelte-check, and optionally
aws.

## Configuration

Options are read at **call time**, via
`zstyle ':omz:plugins:tupperclaude' <key> <value>` with a `CLAUDE_DOCKER_*` environment
variable fallback and a hard-coded default. Because they're resolved at call time, not
plugin-load time, `zstyle` lines work anywhere in `.zshrc` — before or after
`plugins=(...)`.

**oh-my-zsh users:** put your `zstyle` overrides in `~/.zshrc` before `source
$ZSH/oh-my-zsh.sh`, or in `$ZSH_CUSTOM/tupperclaude.zsh` (anything in `$ZSH_CUSTOM` is
auto-sourced). Both work; the `zstyle` layer has no load-order requirement of its own.

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

- **zstyle:** `zstyle ':omz:plugins:tupperclaude' aws <yes|no>` (boolean: `zstyle -t` semantics)
- **env var:** `CLAUDE_DOCKER_INCLUDE_AWS`
- **default:** off
- **read at:** build time

Includes AWS CLI v2 in the image. Off by default to keep the image smaller.

```zsh
export CLAUDE_DOCKER_INCLUDE_AWS=1
claude-docker-arm-build
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
trees together and they can never collapse onto each other.

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
sidecar container (`claude-ts-<mangled-path>`). The Claude container joins that
sidecar's network namespace with `--network=container:...`, so it inherits the tunnel
without needing `NET_ADMIN` or `/dev/net/tun` itself — the sidecar holds the privileges,
the Claude container stays unprivileged.

`claude-ts-ensure` runs before every launch and checks that the sidecar is genuinely
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

4. Point the plugin at it in `~/.zshrc`:

   ```zsh
   export CLAUDE_DOCKER_OP_TS_REF='op://Private/Tailscale/authkey'
   ```

The reference is not a secret, so it is safe in a dotfiles repo.

If the vault is locked or signed out, `claude-ts-ensure` (and `claude-docker-doctor`)
say so and tell you to run `op signin`, rather than misreporting a missing key.

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
`home` option). Shared across all sessions: the Claude credentials file and the cargo
registry cache.

**Credentials.** Host credential stores (`~/.ssh`, `gh`, `gcloud`, Linear, Pulumi, `~/.aws`)
are mounted read-only at `/run/host-*` and copied to their real locations at container
startup, so the container can modify them freely without ever writing to your host
files. Only paths that actually exist are mounted — a bind mount of a missing path would
make Docker create a root-owned empty directory on the host, so tupperclaude checks
first. A Pulumi access token is derived from the credentials file when
`PULUMI_ACCESS_TOKEN` isn't already set, so both the CLI and the Pulumi MCP server
authenticate.

**Git worktrees.** If the working directory is a git worktree, the main checkout is also
mounted at its own path so git can follow the `.git` file's gitdir pointer.

## Privacy note

The build bakes a whitelist of your **own** Claude Code config into the image:
`~/.claude.json`, `~/.claude/CLAUDE.md`, `settings.json`, `skills/`, `commands/`, and
plugin metadata. Credentials are *not* baked — they are mounted at run time.

`~/.claude.json` can still contain MCP server definitions with inline API keys. The build
warns when it spots key/token-shaped fields. **Treat the built image as private: do not
push `claude-code-full-*` to a shared or public registry.**

## Supply chain

Every third-party component follows the same policy:

- an exact version is pinned via a Dockerfile `ARG` — never `latest`, never
  `releases/latest`
- the artifact is verified against a vendor-published `sha256` before it is used
- apt repositories are pinned to a vendor keyring (`signed-by=`)
- npm packages are pinned exactly and installed with `--ignore-scripts`, which blocks the
  most common npm supply-chain vector

Two deliberate exceptions, both documented at their layers:

- **uv** is pinned by immutable image digest (`COPY --from=...@sha256:...`), which is a
  stronger guarantee than a file checksum and covers both architectures from one pin.
- **Claude Code** tracks the `latest` channel by design, so the image matches a freshly
  upgraded host.

Notably, `pulumi`, `rustup`, `deno`, and `mise` are installed from checksum-verified
release artifacts rather than the vendors' `curl ... | sh` bootstrap scripts, which
publish no checksum.

### Updating pinned versions

Bump the `ARG` in `docker/Dockerfile` and take the new checksum from the vendor's own
published checksum file:

| Component | Where the checksum comes from |
| --- | --- |
| yq | `https://github.com/mikefarah/yq/releases/download/<ver>/checksums` — SHA-256 is column 19 (see the `checksums_hashes_order` file) |
| tailscale | `https://pkgs.tailscale.com/stable/tailscale_<ver>_<arch>.tgz.sha256` |
| pulumi | `https://github.com/pulumi/pulumi/releases/download/v<ver>/pulumi-<ver>-checksums.txt` |
| rustup | `https://static.rust-lang.org/rustup/archive/<ver>/<target>/rustup-init.sha256` |
| deno | `https://github.com/denoland/deno/releases/download/<ver>/deno-<target>.zip.sha256sum` |
| mise | `https://github.com/jdx/mise/releases/download/<ver>/SHASUMS256.txt` |
| uv | `docker manifest inspect ghcr.io/astral-sh/uv:<ver>` for the manifest-list digest |
| aws-cli | AWS publishes a GPG signature but no checksum file. Download `awscli-exe-linux-<slug>-<ver>.zip`, verify the `.sig` against AWS's published public key if you want the strongest guarantee, then record `shasum -a 256` of the zip. |

## Known limitations

- **`claude-docker-amd64-build` on Apple Silicon is untested end to end.** It works
  mechanically — `docker build --platform linux/amd64` cross-builds under QEMU — but a
  full toolchain build under emulation is prohibitively slow (the Rust layer alone can
  take a very long time), and no one has sat through a full run to confirm the result.
  The **arm64 image has been built and verified.** If you're on Apple Silicon, use
  `claude-docker-arm`; reach for `amd64` only if you specifically need x86_64 and are
  prepared for a long, unverified build.

## Troubleshooting

**`claude-ts-ensure: no Tailscale auth key configured`** — see
[Supplying the Tailscale auth key](#supplying-the-tailscale-auth-key).

**`'<node>' did not come online within 45s`** — the command prints Tailscale's own health
messages. Check `docker logs claude-ts-<...>`. A key that was single-use and already
consumed, or an expired key, is the usual cause.

**Tools inside the container can't reach anything, but `tailscale status` looks fine** —
that's the stale-netmap case described in [Networking](#networking). Exit Claude and
relaunch.

**The amd64 build seems to hang on Apple Silicon** — it isn't hung, it's QEMU. See
[Known limitations](#known-limitations). Build arm64 unless you specifically need an
x86_64 image.

**`~/.claude.json is not valid JSON`** — the host config is corrupt; fix it before
building, since it gets baked into the image.

**Something else, or you're not sure where a failure is coming from** — run
`claude-docker-doctor`. It runs every preflight check and prints a fix for each failing
one.

## Uninstall

1. Remove the plugin from `plugins=(...)` in `~/.zshrc` and delete the clone (see
   [INSTALL.md](INSTALL.md) for the path, which depends on your plugin manager).
2. Remove containers, sidecars, and state: `claude-docker-clean`, or manually:

   ```zsh
   docker rm -f $(docker ps -aq --filter label=tupperclaude.dir) 2>/dev/null
   docker ps -a --filter name=claude-ts- -q | xargs -r docker rm -f
   rm -rf ~/.config/claude-docker ~/.config/claude-docker-playwright
   ```

3. Verify nothing was missed:

   ```zsh
   docker ps -a --filter label=tupperclaude.dir --filter name=claude-ts- --format '{{.Names}}'
   ```

   An empty result means it's fully removed.

## License

Dual-licensed under your choice of the MIT License ([LICENSE-MIT](LICENSE-MIT)) or the
BSD 3-Clause License ([LICENSE-BSD](LICENSE-BSD)). SPDX identifier: `MIT OR BSD-3-Clause`.

# claude-code-full — Claude Code in a sandboxed container with a full dev toolchain.
#
# Builds for both linux/arm64 and linux/amd64; pass --platform to select.
#
# The base is `docker/sandbox-templates:claude-code`, published by Docker Inc. —
# it is by far the largest third-party component here (Ubuntu userland, Node,
# git, the Claude sandbox runtime and a native Claude Code install), and it is
# the root of trust that every checksummed layer below ultimately rests on. It
# is pinned to an immutable multi-arch manifest digest, not a floating tag.
#
# Supply-chain policy, applied to every third-party component below:
#   * an exact version is pinned via ARG (never `latest`, never `releases/latest`)
#   * the artifact is verified against a sha256 published by the vendor before use
#   * apt repositories are pinned to a vendor keyring (signed-by=)
#   * npm packages are pinned exactly and installed with --ignore-scripts
#   * every RUN uses `bash -o pipefail`, so a failed download in a pipeline fails
#     the build instead of feeding an empty file to the next stage
#
# There are four deliberate exceptions, each documented again at its own layer:
#
#   1. Claude Code (layer 13) is NOT version-pinned and NOT checksum-verified: it
#      tracks the `latest` channel by design so the image matches a freshly
#      upgraded host, and it is installed through the vendor's own
#      `curl https://claude.ai/install.sh | bash` bootstrap — the one such pipe in
#      this file. Everything else (pulumi, rustup, deno, mise, helm, k9s)
#      deliberately uses the release tarball instead of the vendor's
#      `curl … | sh` script, because only the tarball has a published checksum to
#      verify against.
#   2. aws-cli (layer 10, optional) has no vendor-published checksum file — AWS
#      publishes a GPG signature only. The sha256 in the ARG was computed once
#      from the pinned artifact by us and is verified on every build.
#   3. linear-cli (layer 9) is version-pinned but has no checksum of our own:
#      `deno install jsr:…@X.Y.Z` resolves module integrity against JSR's own
#      per-version manifest, and there is no single artifact for us to hash.
#   4. uv (layer 6) is not an ARG+sha256 pin but a `COPY --from` an immutable
#      image digest. That is stronger, not weaker: the digest covers the whole
#      multi-arch manifest.
#
# Bump ARGs deliberately. To refresh a checksum, take it from the vendor's own
# published checksum file — see README.md, "Updating pinned versions".

# Refresh with: docker buildx imagetools inspect docker/sandbox-templates:claude-code
# and take the top-level index Digest (it must list BOTH linux/amd64 and linux/arm64).
FROM docker/sandbox-templates:claude-code@sha256:7fa049b8d7a0cf10f6a4200148ee475e94fc4fb5ef50dfacc4257699cb9a34bc

USER root

# Every RUN below is a pipeline-safe bash: without this, `sh -c` reports only the
# LAST command's status, so a failed `curl` piped into a writer silently produces
# an empty file and the build fails many layers later with an unrelated error.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# ── Layer 1: Base apt packages + language runtimes ───────────────────────────
RUN apt-get update && apt-get install -y \
    openssh-client curl gnupg lsb-release ca-certificates \
    tmux ripgrep jq tzdata unzip \
    zsh \
    postgresql-client default-mysql-client \
    clang clangd cmake build-essential \
    php php-cli php-mbstring php-xml php-curl \
    python3 python3-pip python3-venv \
    locales \
    && locale-gen en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# ── Layer 2: composer (PHP package manager) ──────────────────────────────────
# The versioned phar is downloaded directly and checked against a sha256 that is
# hardcoded here, exactly like every other layer. The alternative — running
# getcomposer.org's installer and checking it against a hash fetched live from
# the vendor at build time — verifies transport but not identity: the same
# origin serves the installer and the hash that checks it, so a compromised
# origin passes trivially. Hardcoding means a tampered artifact fails the build
# even if the vendor's site is serving a matching hash for it.
ARG COMPOSER_VERSION=2.10.0
ARG COMPOSER_SHA256=a346538851988ead111d11e3cbd7d372eeba44abd0af412e09890d3c21ea6c31
RUN curl -fsSL "https://getcomposer.org/download/${COMPOSER_VERSION}/composer.phar" -o /tmp/composer.phar && \
    echo "${COMPOSER_SHA256}  /tmp/composer.phar" | sha256sum -c - && \
    install -m 0755 /tmp/composer.phar /usr/local/bin/composer && \
    rm -f /tmp/composer.phar

# ── Layer 3: GitHub CLI ──────────────────────────────────────────────────────
# The keyring is downloaded to the file directly (no pipe into a writer) and
# checked non-empty before apt is pointed at it: a zero-byte keyring is accepted
# silently at install time and only surfaces as an opaque apt signature error.
# The optional Google Cloud layer near the end of this file applies the same
# keyring pattern through a pipe; see the note there for why that is also safe.
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /usr/share/keyrings/githubcli-archive-keyring.gpg && \
    [ -s /usr/share/keyrings/githubcli-archive-keyring.gpg ] && \
    chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list && \
    apt-get update && apt-get install -y gh && rm -rf /var/lib/apt/lists/*

# ── Layer 4: yq (YAML processor) ─────────────────────────────────────────────
ARG YQ_VERSION=v4.53.2
ARG YQ_SHA256_ARM64=03061b2a50c7a498de2bbb92d7cb078ce433011f085a4994117c2726be4106ea
ARG YQ_SHA256_AMD64=d56bf5c6819e8e696340c312bd70f849dc1678a7cda9c2ad63eebd906371d56b
RUN arch="$(dpkg --print-architecture)" && \
    case "$arch" in \
      arm64) sha="$YQ_SHA256_ARM64" ;; \
      amd64) sha="$YQ_SHA256_AMD64" ;; \
      *) echo "unsupported arch for yq: $arch" >&2; exit 1 ;; \
    esac && \
    curl -fsSL "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${arch}" -o /usr/local/bin/yq && \
    echo "${sha}  /usr/local/bin/yq" | sha256sum -c - && \
    chmod +x /usr/local/bin/yq

# ── Layer 5: Tailscale CLI (client only — tailscaled runs in the sidecar) ────
# claude-docker joins a per-directory Tailscale sidecar's network namespace, so
# the tunnel is already up; this only adds the CLI so `tailscale status/ip/ping/
# whois` work from inside. The sidecar shares its control socket through a named
# volume mounted at /var/run/tailscale (see the claude-ts-ensure function);
# tailscaled chmods that socket 0666 and authorises by peer credentials, so the
# unprivileged `agent` user gets read-only ops and `sudo tailscale …` gets the
# rest. tailscaled itself is deliberately not installed — the sidecar owns it.
ARG TAILSCALE_VERSION=1.98.9
ARG TAILSCALE_SHA256_ARM64=fa554ee808d7d07ee8e3ebbc0215ea087157e2a0abbf408e6e18ea7532554db6
ARG TAILSCALE_SHA256_AMD64=11be30ad301d48f84ff52fec34f8a2f78eb3e3dee1be4e9624d19fccc8df5540
RUN arch="$(dpkg --print-architecture)" && \
    case "$arch" in \
      arm64) sha="$TAILSCALE_SHA256_ARM64" ;; \
      amd64) sha="$TAILSCALE_SHA256_AMD64" ;; \
      *) echo "unsupported arch for tailscale: $arch" >&2; exit 1 ;; \
    esac && \
    curl -fsSL "https://pkgs.tailscale.com/stable/tailscale_${TAILSCALE_VERSION}_${arch}.tgz" -o /tmp/tailscale.tgz && \
    echo "${sha}  /tmp/tailscale.tgz" | sha256sum -c - && \
    tar -xzf /tmp/tailscale.tgz -C /tmp && \
    install -m 0755 "/tmp/tailscale_${TAILSCALE_VERSION}_${arch}/tailscale" /usr/local/bin/tailscale && \
    rm -rf /tmp/tailscale.tgz "/tmp/tailscale_${TAILSCALE_VERSION}_${arch}"

# ── Layer 6: uv (fast Python package manager) ────────────────────────────────
# Copy BOTH uv and uvx: a baked ~/.claude.json may run MCP servers via uvx, so
# the image must ship it. (The build function rewrites the macOS path
# /opt/homebrew/bin/uvx → /usr/local/bin/uvx in the baked config.)
# EXCEPTION 4: not an ARG+sha256 like every other layer, but pinned by immutable
# image digest — which is stronger than a sha256 of a single file:
# the digest covers the whole multi-arch manifest, so arm64 and amd64 both
# resolve from the same pin.
COPY --from=ghcr.io/astral-sh/uv:0.11.18@sha256:78bc42400d77b0678ba95765305c826652ed5431f399257271dda681d0318f03 /uv /usr/local/bin/uv
COPY --from=ghcr.io/astral-sh/uv:0.11.18@sha256:78bc42400d77b0678ba95765305c826652ed5431f399257271dda681d0318f03 /uvx /usr/local/bin/uvx

# ── Layer 7: Pulumi CLI (IaC) ────────────────────────────────────────────────
# Installed under /usr/local so the non-root `agent` user can run pulumi (a /root
# or ~/.pulumi install would be unreadable/private). Auth is supplied at runtime
# via a mounted ~/.pulumi/credentials.json and/or PULUMI_ACCESS_TOKEN. The Python
# SDK is a per-project uv dependency, so nothing language-specific is global.
#
# The release tarball is used rather than `curl get.pulumi.com | sh`, because
# only the tarball has a published checksum to verify against.
ARG PULUMI_VERSION=3.244.0
ARG PULUMI_SHA256_ARM64=7e00db7b42dd943c1e64daa05dcb46a2b7a59defa6534658875504b2c46fed46
ARG PULUMI_SHA256_AMD64=79c6485320055e14a9e1235e0fcb06a966b2e7638299a7c9683e1f3dcfe3414d
ENV PATH=/usr/local/pulumi/bin:$PATH
RUN arch="$(dpkg --print-architecture)" && \
    case "$arch" in \
      arm64) sha="$PULUMI_SHA256_ARM64"; slug=linux-arm64 ;; \
      amd64) sha="$PULUMI_SHA256_AMD64"; slug=linux-x64 ;; \
      *) echo "unsupported arch for pulumi: $arch" >&2; exit 1 ;; \
    esac && \
    curl -fsSL "https://github.com/pulumi/pulumi/releases/download/v${PULUMI_VERSION}/pulumi-v${PULUMI_VERSION}-${slug}.tar.gz" -o /tmp/pulumi.tgz && \
    echo "${sha}  /tmp/pulumi.tgz" | sha256sum -c - && \
    mkdir -p /usr/local/pulumi/bin && \
    tar -xzf /tmp/pulumi.tgz -C /usr/local/pulumi/bin --strip-components=1 && \
    rm -f /tmp/pulumi.tgz && \
    chmod -R a+rX /usr/local/pulumi

# ── Layer 8: Rust toolchain + dev tools (rustfmt, clippy, rust-analyzer) ─────
# Installed under /usr/local (world-readable) so the non-root `agent` user can
# read the toolchain and run cargo/rustc. A /root install (mode 700) leaves the
# binaries unreadable for agent. RUSTUP_HOME is pinned so the rustup proxies find
# the shared toolchain; CARGO_HOME is exported only for the install, so at runtime
# it defaults to the writable ~/.cargo (agent's own crate cache). The default
# rustup profile already bundles rustfmt and clippy; we add rust-analyzer for LSP.
#
# rustup-init is fetched from the versioned archive path (not sh.rustup.rs) so it
# can be checksum-verified like everything else.
ENV RUSTUP_HOME=/usr/local/rustup
ENV PATH=/usr/local/cargo/bin:$PATH
ARG RUST_TOOLCHAIN=1.96.0
ARG RUSTUP_VERSION=1.29.0
ARG RUSTUP_SHA256_ARM64=9732d6c5e2a098d3521fca8145d826ae0aaa067ef2385ead08e6feac88fa5792
ARG RUSTUP_SHA256_AMD64=4acc9acc76d5079515b46346a485974457b5a79893cfb01112423c89aeb5aa10
RUN arch="$(dpkg --print-architecture)" && \
    case "$arch" in \
      arm64) sha="$RUSTUP_SHA256_ARM64"; target=aarch64-unknown-linux-gnu ;; \
      amd64) sha="$RUSTUP_SHA256_AMD64"; target=x86_64-unknown-linux-gnu ;; \
      *) echo "unsupported arch for rustup: $arch" >&2; exit 1 ;; \
    esac && \
    curl --proto '=https' --tlsv1.2 -fsSL \
      "https://static.rust-lang.org/rustup/archive/${RUSTUP_VERSION}/${target}/rustup-init" -o /tmp/rustup-init && \
    echo "${sha}  /tmp/rustup-init" | sha256sum -c - && \
    chmod +x /tmp/rustup-init && \
    CARGO_HOME=/usr/local/cargo /tmp/rustup-init -y --no-modify-path --default-toolchain "$RUST_TOOLCHAIN" && \
    rm -f /tmp/rustup-init && \
    CARGO_HOME=/usr/local/cargo rustup component add rust-analyzer && \
    chmod -R a+rX /usr/local/rustup /usr/local/cargo

# ── Layer 9: Deno + linear-cli ──────────────────────────────────────────────
# DENO_DIR holds the pre-built module cache; owned by `agent` so the CLI can also
# write the runtime v8 code cache there (read-only would fail with CannotOpen).
# The release zip is used rather than `curl deno.land/install.sh | sh`, because
# only the zip has a published .sha256sum to verify against.
#
# EXCEPTION 3: linear-cli is pinned to an exact JSR version. There is no artifact for
# us to checksum — `deno install jsr:…@X.Y.Z` resolves the package against JSR's
# own per-version integrity manifest — so the version pin is the whole guarantee,
# which makes an exact pin (rather than a bare `jsr:@schpet/linear-cli`) the only
# thing standing between this image and whatever the registry serves that minute.
# Security over newness, as with the npm globals: the pin trails the newest
# release so a compromised publish has a window to be caught before it lands here.
ENV DENO_DIR=/usr/local/lib/deno-cache
ARG DENO_VERSION=v2.8.2
ARG LINEAR_CLI_VERSION=2.3.0
ARG DENO_SHA256_ARM64=48647189aee6454ed9b9852fa700a77f92b39465c04c625901d165bc8e937afc
ARG DENO_SHA256_AMD64=184da7a5267ab649bc08821b3bc3ce6805d8e6985fb82707cb8d5e9fd6535362
RUN arch="$(dpkg --print-architecture)" && \
    case "$arch" in \
      arm64) sha="$DENO_SHA256_ARM64"; target=aarch64-unknown-linux-gnu ;; \
      amd64) sha="$DENO_SHA256_AMD64"; target=x86_64-unknown-linux-gnu ;; \
      *) echo "unsupported arch for deno: $arch" >&2; exit 1 ;; \
    esac && \
    curl -fsSL "https://github.com/denoland/deno/releases/download/${DENO_VERSION}/deno-${target}.zip" -o /tmp/deno.zip && \
    echo "${sha}  /tmp/deno.zip" | sha256sum -c - && \
    unzip -q /tmp/deno.zip -d /tmp/deno && \
    install -m 0755 /tmp/deno/deno /usr/local/bin/deno && \
    rm -rf /tmp/deno.zip /tmp/deno && \
    deno install --allow-all --global --name linear "jsr:@schpet/linear-cli@${LINEAR_CLI_VERSION}" && \
    cp -r /root/.deno/bin/.linear /usr/local/lib/linear-deno && \
    chmod -R a+rX /usr/local/lib/linear-deno && \
    chown -R agent:agent /usr/local/lib/deno-cache && \
    cp /root/.deno/bin/linear /usr/local/bin/linear && \
    sed -i 's|/root/.deno/bin/.linear/|/usr/local/lib/linear-deno/|g' /usr/local/bin/linear

# ── Layer 10 (optional): AWS CLI v2 ──────────────────────────────────────────
# Off by default; enable with --build-arg INCLUDE_AWS=1 (the zsh plugin sets this
# when CLAUDE_DOCKER_INCLUDE_AWS is exported).
#
# EXCEPTION 2: AWS publishes GPG signatures for these bundles but no checksum
# file, so the sha256 below is not vendor-published — it was computed once by us
# from the pinned artifact, and is verified on every build. See README.md.
ARG INCLUDE_AWS=0
ARG AWSCLI_VERSION=2.36.17
ARG AWSCLI_SHA256_ARM64=a820e168234363fb630da717111b6d94e6cd3712e3552da340e9910420d17cac
ARG AWSCLI_SHA256_AMD64=7e3b004e49c4550729fddbdc7f199b07b2288fe73a41ac0fcc8f5b873c938f7b
RUN if [ "$INCLUDE_AWS" = "1" ]; then \
      arch="$(dpkg --print-architecture)" && \
      case "$arch" in \
        arm64) sha="$AWSCLI_SHA256_ARM64"; slug=aarch64 ;; \
        amd64) sha="$AWSCLI_SHA256_AMD64"; slug=x86_64 ;; \
        *) echo "unsupported arch for aws-cli: $arch" >&2; exit 1 ;; \
      esac && \
      curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${slug}-${AWSCLI_VERSION}.zip" -o /tmp/awscli.zip && \
      echo "${sha}  /tmp/awscli.zip" | sha256sum -c - && \
      unzip -q /tmp/awscli.zip -d /tmp && \
      /tmp/aws/install --install-dir /usr/local/aws-cli --bin-dir /usr/local/bin && \
      rm -rf /tmp/awscli.zip /tmp/aws && \
      chmod -R a+rX /usr/local/aws-cli ; \
    fi

# ── Layer 11 (optional): Google Cloud SDK + GKE auth plugin ──────────────────
# Off by default; enable with --build-arg INCLUDE_GCLOUD=1.
#
# Position matters more than it looks. This used to be layer 4, where the build
# arg became part of the cache key for every layer below it — so toggling the
# option re-ran the Rust toolchain, deno, pulumi, uv, tailscale and yq: ~2.3 GB
# and most of a 15-minute build, every time, forever. Down here it forks only
# the same tail INCLUDE_AWS already forks.
#
# That tail is not free: an ARG exports into the environment of every later
# instruction, so mise and the two npm layers below still rebuild on a toggle.
# Hoisting them above this block would fix that, but they run as USER agent and
# moving them means shuffling the USER switches — worth doing, not done here.
#
# With the option off, /etc/apt/sources.list.d/google-cloud-sdk.list is never
# written either, so a default image carries no third-party apt repo that an
# in-sandbox `apt-get install` would silently consult.
#
# Apt packages, so the keyring is what is pinned rather than a version — the
# same policy layer 3 applies to gh, not an exception to it.
#
# Safe to pipe: `set -o pipefail` (SHELL, above) propagates a curl failure, and
# gpg --dearmor rejects empty input rather than writing an empty keyring. The
# keyring is then checked non-empty before apt is pointed at it — an empty one
# is accepted silently and surfaces only as an opaque signature error.
#
# gke-gcloud-auth-plugin rides along with gcloud rather than with k8s: it
# declares no dependencies at all (~9 MB), and it is useless without the SDK,
# which mints the tokens it hands to kubectl.
ARG INCLUDE_GCLOUD=0
RUN if [ "$INCLUDE_GCLOUD" = "1" ]; then \
      curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
        | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg && \
      [ -s /usr/share/keyrings/cloud.google.gpg ] && \
      echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
        > /etc/apt/sources.list.d/google-cloud-sdk.list && \
      apt-get update && \
      apt-get install -y google-cloud-cli google-cloud-cli-gke-gcloud-auth-plugin && \
      rm -rf /var/lib/apt/lists/* ; \
    fi

# ── Layer 12 (optional): kubectl, helm and k9s ───────────────────────────────
# Off by default; enable with --build-arg INCLUDE_K8S=1.
#
# HELM_MAJOR selects which helm ships: 3, 4, or both. The two majors are both
# maintained and charts written for 3 do not all render under 4, so the choice
# is the user's. Bare `helm` is a symlink — helm does not dispatch on argv[0],
# so a copy would cost another 55-60 MB for nothing — and under `both` it points
# at helm3, the conservative default.
#
# Both helm tarballs unpack to the same linux-<arch>/ directory, hence the rm
# between them; the k9s tarball is FLAT, so it is extracted into a directory of
# its own rather than scattering LICENSE and README.md across /tmp.
#
# k9s is ~123 MB of the ~235 MB this layer adds. That is the only artifact its
# vendor publishes — there is no slimmer build to prefer.
ARG INCLUDE_K8S=0
ARG HELM_MAJOR=3
ARG KUBECTL_VERSION=v1.36.3
ARG KUBECTL_SHA256_ARM64=3d86f24401c41ae5a46ac50eef8865fe891d3647d324a0836f6c63757a126e62
ARG KUBECTL_SHA256_AMD64=ebbd080e7c2e275093b55915722043257eb24004363e20acb3c4d71919f88336
ARG HELM3_VERSION=v3.21.3
ARG HELM3_SHA256_ARM64=67f58155079ff9ffab98ba5c88daff0ed9b542f3a4732f5dd426dde7dd0f5244
ARG HELM3_SHA256_AMD64=15e041a93a590dce8100f39385cd98c84a765c9e36aeeb9e2dc6ff9e4769e2e0
ARG HELM4_VERSION=v4.2.3
ARG HELM4_SHA256_ARM64=21abd9354d39b2cd79a8d76be6912cd137a983cbf997193503fb8a6a6e2f2785
ARG HELM4_SHA256_AMD64=e9b88b4ee95b18c706839c28d3a0220e5bc470e9cd9262410c90793c45ff8b7c
ARG K9S_VERSION=v0.51.0
ARG K9S_SHA256_ARM64=3ee05c82e5f9198928a4e86133608ba6a2c10a2244d6a7789e820f78319d640c
ARG K9S_SHA256_AMD64=c3752ad51a5a4015a113819c4eeb6e55a4d0e4b8e652494797532f6fc8161dd7
RUN if [ "$INCLUDE_K8S" = "1" ]; then \
      arch="$(dpkg --print-architecture)" && \
      case "$arch" in \
        arm64) kubectl_sha="$KUBECTL_SHA256_ARM64"; helm3_sha="$HELM3_SHA256_ARM64"; helm4_sha="$HELM4_SHA256_ARM64"; k9s_sha="$K9S_SHA256_ARM64" ;; \
        amd64) kubectl_sha="$KUBECTL_SHA256_AMD64"; helm3_sha="$HELM3_SHA256_AMD64"; helm4_sha="$HELM4_SHA256_AMD64"; k9s_sha="$K9S_SHA256_AMD64" ;; \
        *) echo "unsupported arch for the k8s toolchain: $arch" >&2; exit 1 ;; \
      esac && \
      case "$HELM_MAJOR" in \
        3|4|both) : ;; \
        *) echo "HELM_MAJOR must be 3, 4 or both: got '$HELM_MAJOR'" >&2; exit 1 ;; \
      esac && \
      curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${arch}/kubectl" -o /usr/local/bin/kubectl && \
      echo "${kubectl_sha}  /usr/local/bin/kubectl" | sha256sum -c - && \
      chmod +x /usr/local/bin/kubectl && \
      if [ "$HELM_MAJOR" = "3" ] || [ "$HELM_MAJOR" = "both" ]; then \
        curl -fsSL "https://get.helm.sh/helm-${HELM3_VERSION}-linux-${arch}.tar.gz" -o /tmp/helm3.tgz && \
        echo "${helm3_sha}  /tmp/helm3.tgz" | sha256sum -c - && \
        tar -xzf /tmp/helm3.tgz -C /tmp "linux-${arch}/helm" && \
        install -m 0755 "/tmp/linux-${arch}/helm" /usr/local/bin/helm3 && \
        rm -rf /tmp/helm3.tgz "/tmp/linux-${arch}" ; \
      fi && \
      if [ "$HELM_MAJOR" = "4" ] || [ "$HELM_MAJOR" = "both" ]; then \
        curl -fsSL "https://get.helm.sh/helm-${HELM4_VERSION}-linux-${arch}.tar.gz" -o /tmp/helm4.tgz && \
        echo "${helm4_sha}  /tmp/helm4.tgz" | sha256sum -c - && \
        tar -xzf /tmp/helm4.tgz -C /tmp "linux-${arch}/helm" && \
        install -m 0755 "/tmp/linux-${arch}/helm" /usr/local/bin/helm4 && \
        rm -rf /tmp/helm4.tgz "/tmp/linux-${arch}" ; \
      fi && \
      if [ "$HELM_MAJOR" = "4" ]; then \
        ln -sf /usr/local/bin/helm4 /usr/local/bin/helm ; \
      else \
        ln -sf /usr/local/bin/helm3 /usr/local/bin/helm ; \
      fi && \
      curl -fsSL "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_${arch}.tar.gz" -o /tmp/k9s.tgz && \
      echo "${k9s_sha}  /tmp/k9s.tgz" | sha256sum -c - && \
      mkdir -p /tmp/k9s && tar -xzf /tmp/k9s.tgz -C /tmp/k9s k9s && \
      install -m 0755 /tmp/k9s/k9s /usr/local/bin/k9s && \
      rm -rf /tmp/k9s.tgz /tmp/k9s ; \
    fi

# ── versions command ─────────────────────────────────────────────────────────
RUN printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -uo pipefail' \
  'pad() { printf "%-28s" "$1"; }' \
  'v()  { pad "$1"; shift; "$@" 2>&1 | head -1 || echo "(not found)"; }' \
  '' \
  'echo "=== claude-code-full tool versions ==="' \
  'echo ""' \
  'v "claude"                claude --version' \
  'v "gh"                    gh --version' \
  'v "gcloud"                gcloud --version' \
  'v "kubectl"               kubectl version --client' \
  'v "helm"                  helm version --short' \
  'v "k9s"                   k9s version --short' \
  'v "ripgrep (rg)"          rg --version' \
  'v "yq"                    yq --version' \
  'v "tmux"                  tmux -V' \
  'v "uv"                    uv --version' \
  'v "mise"                  mise --version' \
  'v "git"                   git --version' \
  'v "node"                  node --version' \
  'v "npm"                   npm --version' \
  'v "psql"                  psql --version' \
  'v "mysql"                 mysql --version' \
  'v "python3"               python3 --version' \
  'v "pip3"                  pip3 --version' \
  'v "php"                   php --version' \
  'v "composer"              composer --version' \
  'v "rustc"                 rustc --version' \
  'v "cargo"                 cargo --version' \
  'v "rustfmt"               cargo fmt --version' \
  'v "clippy"                cargo clippy --version' \
  'v "rust-analyzer"         rust-analyzer --version' \
  'v "clang"                 clang --version' \
  'v "clangd"                clangd --version' \
  'v "cmake"                 cmake --version' \
  'v "pyright"               pyright --version' \
  'v "typescript-lsp"        typescript-language-server --version' \
  'v "svelte-check"          svelte-check --version' \
  'v "pnpm"                  pnpm --version' \
  'v "yarn"                  yarn --version' \
  'v "bun"                   bun --version' \
  'v "deno"                  deno --version' \
  'v "linear"                linear --version' \
  'v "pulumi"                pulumi version' \
  'v "tailscale"             tailscale version' \
  'v "aws"                   aws --version' \
  'v "docker (host socket)"  docker --version' \
  'echo ""' \
  > /usr/local/bin/versions && chmod +x /usr/local/bin/versions

# ── Startup script: copy host credentials into writable container paths ──────
# Mounts land at /run/host-* (read-only); this script copies them to the real
# locations so the container can modify them freely without touching host files.
RUN printf '%s\n' \
  '#!/bin/bash' \
  'set -e' \
  'if [ -d /run/host-ssh ]; then' \
  '    mkdir -p ~/.ssh' \
  '    cp -r /run/host-ssh/. ~/.ssh/' \
  '    sed -i "/^\s*UseKeychain/d; /^\s*AddKeysToAgent/d" ~/.ssh/config 2>/dev/null || true' \
  '    chmod 700 ~/.ssh' \
  '    find ~/.ssh -maxdepth 1 ! -name "*.pub" -type f -exec chmod 600 {} \;' \
  'fi' \
  'if [ -d /run/host-gh ]; then' \
  '    mkdir -p ~/.config/gh' \
  '    cp -r /run/host-gh/. ~/.config/gh/' \
  'fi' \
  'if [ -d /run/host-gcloud ]; then' \
  '    mkdir -p ~/.config/gcloud' \
  '    cp -r /run/host-gcloud/. ~/.config/gcloud/' \
  'fi' \
  '# Only ~/.kube/config is mounted, never the whole ~/.kube: the rest is a' \
  '# discovery cache keyed by API-server IP (an inventory of every cluster the' \
  '# host has ever reached) plus a live GKE access token, none of which the' \
  '# sandbox needs. The copy is writable, so `gcloud container clusters' \
  '# get-credentials` in here adds contexts the host file never sees.' \
  'if [ -f /run/host-kube/config ]; then' \
  '    mkdir -p ~/.kube' \
  '    cp /run/host-kube/config ~/.kube/config' \
  '    chmod 700 ~/.kube' \
  '    chmod 600 ~/.kube/config' \
  '    # A kubeconfig written on macOS names the Homebrew path for the GKE auth' \
  '    # plugin, which does not exist here. Rewrite it to the bare binary and' \
  '    # let $PATH resolve it. Guarded alone, not around the copy above: a' \
  '    # kubeconfig with no such stanza is normal, a failed copy is not.' \
  '    # The character class is path characters only, so a YAML-quoted value' \
  '    # keeps its quotes; [^ ]* would swallow the opening one and strip it.' \
  '    # Double-quoted because the expression holds [ ] and *: bare, the shell' \
  '    # would glob it against the mounted repo that is cwd here.' \
  '    sed -i "s#[A-Za-z0-9_./-]*/gke-gcloud-auth-plugin#gke-gcloud-auth-plugin#g" ~/.kube/config || true' \
  'fi' \
  'if [ -d /run/host-linear ]; then' \
  '    mkdir -p ~/.config/linear' \
  '    cp -r /run/host-linear/. ~/.config/linear/' \
  'fi' \
  'if [ -d /run/host-aws ]; then' \
  '    mkdir -p ~/.aws' \
  '    cp -r /run/host-aws/. ~/.aws/' \
  '    chmod 700 ~/.aws' \
  'fi' \
  'if [ -f /run/host-pulumi/credentials.json ]; then' \
  '    mkdir -p ~/.pulumi' \
  '    cp /run/host-pulumi/credentials.json ~/.pulumi/credentials.json' \
  '    chmod 600 ~/.pulumi/credentials.json' \
  '    # The pulumi CLI reads credentials.json, but the pulumi MCP server reads' \
  '    # PULUMI_ACCESS_TOKEN. Derive the token from the creds file when the env' \
  '    # var was not already forwarded, so both auth paths work.' \
  '    if [ -z "${PULUMI_ACCESS_TOKEN:-}" ]; then' \
  '        export PULUMI_ACCESS_TOKEN="$(jq -r ".accessTokens[\"https://api.pulumi.com\"] // empty" ~/.pulumi/credentials.json)"' \
  '    fi' \
  'fi' \
  'exec "$@"' \
  > /usr/local/bin/start.sh && chmod +x /usr/local/bin/start.sh

USER agent

# ── Layer 13: mise (runtime version manager — must not shadow system node) ───
# Installed from the release binary + published SHASUMS256.txt entry rather than
# `curl mise.run | sh`, so it is verified like everything else.
ARG MISE_VERSION=v2026.5.18
ARG MISE_SHA256_ARM64=3c19d4861684e4ed5b8d020bcbdd99f478df43583fb767bd8a663983d4a4e209
ARG MISE_SHA256_AMD64=cfac593469d028d7ae5fe36e37bd7c59118b5238e92d8a876209578464f24a84
RUN arch="$(dpkg --print-architecture)" && \
    case "$arch" in \
      arm64) sha="$MISE_SHA256_ARM64"; slug=linux-arm64 ;; \
      amd64) sha="$MISE_SHA256_AMD64"; slug=linux-x64 ;; \
      *) echo "unsupported arch for mise: $arch" >&2; exit 1 ;; \
    esac && \
    mkdir -p "$HOME/.local/bin" && \
    curl -fsSL "https://github.com/jdx/mise/releases/download/${MISE_VERSION}/mise-${MISE_VERSION}-${slug}" -o "$HOME/.local/bin/mise" && \
    echo "${sha}  $HOME/.local/bin/mise" | sha256sum -c - && \
    chmod +x "$HOME/.local/bin/mise" && \
    echo 'eval "$($HOME/.local/bin/mise activate bash)"' >> ~/.bashrc

# ── Layer 14: npm-based LSP servers + SvelteKit stack ────────────────────────
# pyright / typescript-language-server back the pyright-lsp / typescript-lsp
# plugins. For SvelteKit we add the Svelte language server + svelte-check
# (.svelte type-checking/diagnostics) — there is no official svelte-lsp plugin,
# so the binaries are provided directly — and pnpm/yarn, the package managers
# SvelteKit projects commonly use (npm is already present; Vite/Vitest and the
# @sveltejs/* packages are per-project deps, not global).
# Security over newness: every package is pinned to an exact, known-good version
# (no @latest), and installed with --ignore-scripts to block malicious lifecycle
# scripts — the most common npm supply-chain vector. typescript pinned to a
# mature 5.x (not the brand-new 6.0); pnpm to v10 (v11 needs newer Node than the
# base's v20.19). Bump these deliberately, not implicitly.
RUN npm install -g --ignore-scripts \
      typescript@5.9.3 \
      typescript-language-server@5.3.0 \
      pyright@1.1.410 \
      svelte-language-server@0.18.1 \
      svelte-check@4.5.0 \
      pnpm@10.34.1 \
      yarn@1.22.22
# bun must run its postinstall to fetch the platform binary, so it cannot use
# --ignore-scripts; pinned exact instead.
RUN npm install -g bun@1.3.14

# ── Layer 15 (per-build cache-bust): update claude-code ──────────────────────
# The base image installs Claude Code natively (~/.local/bin via install.sh).
# Re-run the same native installer to pull the latest build, rather than adding a
# second copy via `npm install -g` (which `/doctor` flags as a leftover/duplicate
# install shadowed on PATH by the native one).
#
# EXCEPTION 1 to the supply-chain policy at the top of this file. This is the one
# component deliberately NOT version-pinned and NOT checksum-verified: it tracks
# the `latest` channel so the image matches a freshly `--upgrade`d host, and it
# is installed through the vendor's own `curl … | bash` bootstrap — the only such
# pipe here. Every other vendor that offers one (pulumi, rustup, deno, mise) is
# installed from the release tarball instead, precisely because the tarball has a
# published checksum and the bootstrap script does not. There is no version to
# pin and no published hash for a moving channel, so the trust here is in TLS to
# claude.ai plus `set -o pipefail`, which at least makes a failed download fail
# the build rather than silently no-op (bash on empty stdin exits 0).
#
# BUILD_DATE carries a per-build timestamp (set by the build function), so this
# layer re-runs on every build and always fetches the newest release.
ARG BUILD_DATE=unknown
RUN echo "Build date: $BUILD_DATE" && curl -fsSL https://claude.ai/install.sh | bash -s latest

# ── Layer 16: baked non-secret config ────────────────────────────────────────
# claude.json      = ~/.claude.json  (account prefs, non-secret)
# claude-settings/ = whitelist of ~/.claude/ (skills, plugins, commands,
#                    CLAUDE.md, settings.json)
# Credentials are NOT baked — they are mounted at run time.
COPY --chown=agent:agent claude.json      /home/agent/.claude.json
COPY --chown=agent:agent claude-settings/ /home/agent/.claude/

ENV CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1

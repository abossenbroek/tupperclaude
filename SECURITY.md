# Security policy

## Reporting a vulnerability

**Do not open a public issue.** Use GitHub's private vulnerability reporting:

> [Report a vulnerability](https://github.com/abossenbroek/tupperclaude/security/advisories/new)

Or email anton@bossenbroek.ai.

Expect an acknowledgement within a week. This is a personal project maintained in spare
time; read that as a genuine estimate rather than an SLA.

## What is in scope

tupperclaude runs Claude Code in a container that is handed a lot: your forwarded SSH
agent, a copy of `~/.ssh`, `gh`, `gcloud`, `aws`, `pulumi` and `linear` credentials, your
API keys, and read-write access to the working directory. Anything that widens that beyond
what the documentation describes is worth reporting. In particular:

- credentials reaching the image, a registry, or a log where the docs say they do not
- the build baking in something from the host it should not (see the Privacy note in
  README.md for what is deliberately baked)
- an option that claims to tighten the sandbox but does not — `docker-sock off` is the
  main one
- the Tailscale sidecar exposing more of the tailnet than a sandbox should reach
- a supply-chain gap: an unpinned artifact, a checksum that is not actually verified, or a
  pin that does not match what upstream publishes

## What is not a vulnerability

The sandbox is **not a security boundary against code running inside it**, and the README
says as much. It is a reproducible, disposable environment — its isolation is about not
polluting the host.

These are known and documented, not findings:

- code in the sandbox can use the forwarded SSH agent and the copied cloud credentials
- with `docker-sock on` (the default) the sandbox can reach the host Docker socket, which
  is equivalent to root on the host
- API keys are visible in the `docker run` command line, which means `ps` and `docker inspect`
  show them
- the built image is private by design; `~/.claude.json` can contain inline MCP API keys
  and the build warns when it spots key-shaped fields

If you think one of those is worse than documented — that it grants more than the docs
admit — that is a report worth making. The line is whether reality is worse than the
written promise.

## Supply chain

Third-party components in `docker/Dockerfile` are version-pinned and checksum-verified,
with documented exceptions (Claude Code tracks `latest` by design; aws-cli has no
vendor-published checksum). README.md lists each exception and where every checksum comes
from, letting you re-derive any pin yourself.

A pin that does not match what the vendor publishes is a security report, not a bug
report.

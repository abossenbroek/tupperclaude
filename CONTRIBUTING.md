# Contributing to tupperclaude

## AI assistance notice

> [!IMPORTANT]
>
> If you used **any kind of AI assistance** to make a contribution, disclose it in the
> pull request, along with how far it went.

This project is not neutral on the question and should say so plainly: **most of
tupperclaude was written with Claude Code.** Run `git log` and you will find
`Co-Authored-By: Claude` on the majority of commits. A tool for running Claude Code in a
sandbox, refusing AI-assisted contributions, would be an odd document to write.

So this is not a policy against AI. It is a policy against *undisclosed* AI, and against
the specific failure modes that unreviewed generation brings.

### Disclose, with the extent

Say what the tool did, not merely that one was involved. Useful disclosures:

- > Written primarily by Claude Code; I reviewed every hunk and wrote the tests myself.
- > I used an LLM to understand the zsh completion system. The patch is mine.
- > Claude wrote the implementation and the tests. I verified the mutation test fails
  > without the fix.

"AI was used" tells a reviewer nothing about where to look. The point of disclosure is to
direct scrutiny, not to confess.

### Do not use AI to write the pull request description

Same rule as [Biome's](https://github.com/biomejs/biome/blob/main/CONTRIBUTING.md), for
the same reason: review bandwidth is the scarce resource. A long, confident,
low-signal PR body costs a reviewer more than a three-line one that says what changed and
what you checked. Write it yourself, briefly.

The same goes for review replies and issue comments.

### Evidence, not assertions

The rule that matters most here, and the one generation most often breaks.

**Do not claim a thing passes without showing that it does.** "All tests pass", "this
fixes the bug" and "verified working" are worth nothing on their own — paste the command
and its output. If you did not run it, say you did not run it. A reviewer can work with
an honest gap; they cannot work with a confident false claim, and finding one costs the
trust of everything else in the patch.

### A regression test must fail without the fix

If you fix a bug, prove the test catches it: revert the fix, watch the new test fail,
restore it, watch it pass. Paste that. A test added alongside a fix that would have
passed before the fix is not a regression test — it is decoration, and it will not stop
the bug coming back.

This is not hypothetical. The completion-binding bug in `zsh/tupperclaude.zsh` was
invisible to a 597-test suite because every test sourced the plugin by absolute path and
none started a real shell. The suite was green and the feature was entirely broken.

## Filing a bug

Open a [bug report](https://github.com/abossenbroek/tupperclaude/issues/new?template=bug_report.yml).
The form asks for `claude-docker-doctor` output, the command you ran, how tupperclaude is
installed and which container engine — the four things nearly every diagnosis here needs,
and the four that are slowest to chase afterwards. Blank issues are off for that reason.

Two things worth checking first, because they account for most reports:

- **Read the error.** Every error in this codebase ends with a command you can paste. If
  it named one, run it.
- **A non-Docker-Desktop engine loses SSH agent forwarding.** OrbStack and Colima do not
  synthesise `/run/host-services/ssh-auth.sock`, so `git push` over SSH fails inside the
  sandbox and `claude-docker-doctor` exits non-zero. Known limitation, in README.md.

**Security problems do not go in the issue tracker** — see [SECURITY.md](SECURITY.md).
The sandbox holds your SSH agent and cloud credentials, so a public issue is the wrong
first move.

## Branches

- **`develop`** is the integration branch. Open your PR against it.
- **`main`** only ever holds released code, and is what the Homebrew tap's `--HEAD`
  serves. It moves by a release PR from `develop`, then a tag.

Releases are SemVer and cut from `main` with `make release VERSION=x.y.z`, which runs
`make check`, bumps `.version`, commits and tags. Pushing the tag is what triggers CI to
build the tarball, create the GitHub release and push the stable stanza to the tap.

## Before you open a pull request

```zsh
make hooks     # once — installs the pre-commit gate
make check     # lint + the zsh suite (~1 min). Must pass.
```

Run the slower tiers when you touch what they cover:

| you changed | also run |
|---|---|
| the plugin shim, `$fpath`, completions, anything load-time | `make test-install` |
| `Formula/tupperclaude.rb` or the installed file layout | `make test-brew` |
| `docker/Dockerfile*` | a real build: `claude-docker-build-arm` |

`make test-install` and `make test-brew` need Docker and Homebrew respectively, and take
minutes. CI runs the first; the second is macOS-only and manual.

## House style

Match what is already there rather than what you would have written.

- **Comments carry what the code cannot.** Non-obvious mechanics, invariants, ordering
  constraints, units. Not narrative history, not a defence of the choice against an
  imagined objection, not a restatement of the line below. If a comment can be deleted
  without the reader losing anything, delete it. Heavily commented code is usually code
  that should have been clearer instead.
- **Every error ends with something the user can paste.** `_claude_docker_err` takes the
  message first and pasteable commands after; keep prose out of that second position, it
  renders as a command.
- **Surgical diffs.** Every changed line should trace to the change you are making. Notice
  unrelated dead code? Mention it; do not delete it in the same PR.
- **zsh, not bash.** `local`/`typeset -g` discipline, `emulate -L zsh`, and the tests run
  under `NO_UNSET WARN_CREATE_GLOBAL` — a leaked global fails the suite.

## Commit messages

A subject line of `area: what changed`, then prose explaining *why* — what was broken,
what was tried, what the interlocks are. Look at `git log` for the register. If you used
AI assistance, keep the `Co-Authored-By:` trailer; it is part of the disclosure.

## Code of conduct

[Contributor Covenant 2.1](CODE_OF_CONDUCT.md) applies, with reports to
anton@bossenbroek.ai.

The working norm underneath it: assume the other person is competent and acting in good
faith, ask before assuming a mistake, and keep criticism aimed at code rather than people.
Maintainer time is donated; a contribution that ignores the gates above spends it badly.

Undisclosed AI assistance, or PRs whose descriptions are visibly machine-written, may be
closed without detailed review.

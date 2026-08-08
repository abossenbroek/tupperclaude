# tupperclaude — correctness gates.
#
# Two tiers, split by what they cost:
#
#   make check         seconds.  Lint + the zsh suite. This is what the
#                      pre-commit hook runs, and what must pass before a commit.
#   make test-install  minutes.  Throwaway Linux containers, one per install
#                      variation. Too slow for a hook; runs in CI and on demand.
#
# The split is deliberate: a pre-commit hook people disable because it takes
# four minutes protects nothing at all.

SHELL := /bin/sh
ZSH   ?= zsh

# Every zsh file in the repo, in the same order CI checks them. Kept here rather
# than in the workflow so `make lint` and CI cannot disagree about what "every
# zsh file" means.
ZSH_FILES = \
	zsh/tupperclaude.zsh \
	tupperclaude.plugin.zsh \
	$(wildcard zsh/functions/*) \
	$(wildcard zsh/templates/*.zsh) \
	$(wildcard zsh/tests/*.zsh) \
	$(wildcard zsh/tests/lib/*.zsh) \
	zsh/tests/fake-bin/docker \
	zsh/tests/fake-bin/sleep \
	zsh/completions/_claude-docker

.DEFAULT_GOAL := help
.PHONY: help lint test check test-install test-all hooks unhooks

help: ## Show this help
	@echo "tupperclaude make targets:"
	@echo ""
	@grep -hE '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk -F':.*?## ' '{printf "  %-14s %s\n", $$1, $$2}'
	@echo ""
	@echo "  check         is the pre-commit gate (fast)."
	@echo "  test-install  needs Docker and takes minutes."

lint: ## Syntax-check every zsh file
	@fail=0; for f in $(ZSH_FILES); do \
		$(ZSH) -n "$$f" || { echo "zsh -n failed: $$f"; fail=1; }; \
	done; exit $$fail

test: ## Run the zsh test suite (fake docker, no daemon)
	@$(ZSH) zsh/tests/run-tests.zsh

check: lint test ## Lint + suite. The pre-commit gate.

test-install: ## Install variations in throwaway Linux containers (needs Docker)
	@zsh/tests/docker/run-install-matrix.sh

test-all: check test-install ## Everything, including the slow tests

# Releases are cut from main, which only ever holds released code. Work lands on
# develop; a release PR moves develop to main, and this tags it.
#
# The tag is the trigger: CI builds the tarball and creates the GitHub release.
# Plugin managers install from the repo, so a release is a marker, not a delivery.
release: ## Tag a release from main: make release VERSION=0.2.0
	@test -n "$(VERSION)" || { echo "usage: make release VERSION=0.2.0"; exit 1; }
	@echo "$(VERSION)" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$$' \
	  || { echo "VERSION must be x.y.z (no leading v, no suffix): got '$(VERSION)'"; exit 1; }
	@test "$$(git rev-parse --abbrev-ref HEAD)" = main \
	  || { echo "releases are cut from main; you are on $$(git rev-parse --abbrev-ref HEAD)"; exit 1; }
	@git diff --quiet && git diff --cached --quiet \
	  || { echo "working tree is dirty — commit or stash first"; exit 1; }
	@git rev-parse -q --verify "refs/tags/v$(VERSION)" >/dev/null \
	  && { echo "tag v$(VERSION) already exists"; exit 1; } || true
	@$(MAKE) --no-print-directory check
	@# One shell: whether the bump was committed decides what the rollback below
	@# may safely undo. .version can already hold VERSION when a tag was deleted
	@# and re-cut, and committing nothing must not abort the release.
	@echo "$(VERSION)" > .version; \
	git add .version; \
	if git diff --cached --quiet; then committed=0; \
	else git commit -q -m "release: v$(VERSION)"; committed=1; fi; \
	git tag -s "v$(VERSION)" -m "v$(VERSION)" 2>/dev/null \
	  || { echo "cannot sign the tag — no signing key configured."; \
	       echo "  git config gpg.format ssh"; \
	       echo "  git config user.signingkey ~/.ssh/id_ed25519.pub"; \
	       echo "then register that key at github.com/settings/ssh/new as a Signing Key."; \
	       [ "$$committed" = 1 ] && git reset -q --hard HEAD~1; exit 1; }
	@echo ""
	@echo "Tagged v$(VERSION). Push it to trigger the release:"
	@echo "  git push origin main --follow-tags"

hooks: ## Point git at .githooks (installs the pre-commit gate)
	@git config core.hooksPath .githooks
	@echo "core.hooksPath = .githooks — pre-commit now runs 'make check'."

unhooks: ## Stop using .githooks
	@git config --unset core.hooksPath || true
	@echo "core.hooksPath unset."

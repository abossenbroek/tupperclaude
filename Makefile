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
.PHONY: help lint test check test-install test-brew brew-publish test-all hooks unhooks

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

BREW_TAP_REPO ?= git@github.com:abossenbroek/homebrew-tupperclaude.git

test-brew: ## Package the working tree and build the Homebrew formula (needs brew)
	@zsh/tests/brew/run-formula-test.sh

# The tap's copy is generated, never hand-edited: two writable copies drift, and
# the one that drifts is always the one no gate tests. Run test-brew first —
# this pushes whatever is in Formula/, tested or not.
brew-publish: ## Sync the tested formula into the Homebrew tap and push
	@tmp=$$(mktemp -d); \
	git clone -q $(BREW_TAP_REPO) $$tmp || { echo "could not clone $(BREW_TAP_REPO)"; exit 1; }; \
	cp Formula/tupperclaude.rb $$tmp/Formula/tupperclaude.rb; \
	cd $$tmp && git add -A && \
	  if git diff --cached --quiet; then \
	    echo "tap already matches Formula/tupperclaude.rb — nothing to publish."; \
	  else \
	    git commit -q -m "formula: sync from tupperclaude $$(cat $(CURDIR)/.version)" && \
	    git push -q && echo "published to $(BREW_TAP_REPO)"; \
	  fi; \
	rm -rf $$tmp

test-all: check test-install test-brew ## Everything, including the slow tests

hooks: ## Point git at .githooks (installs the pre-commit gate)
	@git config core.hooksPath .githooks
	@echo "core.hooksPath = .githooks — pre-commit now runs 'make check'."

unhooks: ## Stop using .githooks
	@git config --unset core.hooksPath || true
	@echo "core.hooksPath unset."

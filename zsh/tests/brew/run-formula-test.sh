#!/bin/sh
# run-formula-test.sh — prove the Homebrew formula actually packages THIS tree.
#
# `brew install --HEAD` would clone origin/main, which is not what you are about
# to commit; a formula can be broken on the branch and pass that way. So this
# packages the working tree into a tarball, rewrites the formula's source stanza
# to point at it with a real sha256, and builds that. What gets tested is the
# code in front of you.
#
# Not part of `make check`: it needs Homebrew, and it installs and uninstalls a
# formula in the caller's brew prefix.
#
# It also installs the formula's dependencies (jq, zsh) if they are not already
# there, and brew autoremoves them on uninstall — which restores the prior state
# rather than damaging it, because autoremove only ever touches formulae that
# were installed AS dependencies. One deliberately not "fixed" with
# HOMEBREW_NO_AUTOREMOVE: leaving them behind would be the worse trade.

set -eu

root=$(cd "$(dirname "$0")/../../.." && pwd)
formula="$root/Formula/tupperclaude.rb"

if ! command -v brew >/dev/null 2>&1; then
    echo "run-formula-test.sh: Homebrew not installed — skipping." >&2
    echo "  this target is macOS/brew only; 'make check' is the portable gate." >&2
    exit 0
fi

[ -f "$formula" ] || { echo "no formula at $formula" >&2; exit 1; }

# Checked before anything is created: this test ends by uninstalling
# tupperclaude, which would remove a real installation the user is relying on.
# The keg name is shared no matter which tap a formula came from, so an install
# from anywhere at all is a conflict.
if brew list --formula tupperclaude >/dev/null 2>&1; then
    echo "run-formula-test.sh: tupperclaude is already installed via brew." >&2
    echo "  this test installs and then uninstalls it, which would remove yours." >&2
    echo "  brew uninstall tupperclaude   # then re-run" >&2
    exit 1
fi

# Homebrew 6 rejects path-based formulae ("Homebrew requires formulae to be in a
# tap") for both `audit` and `install`, so the formula is dropped into a
# throwaway local tap and removed again afterwards. The tap name is
# test-specific so it cannot collide with a real one the user has.
TAP=tupperclaude/local-test
work=$(mktemp -d)

# Untap and uninstall in the trap: a failed `brew test` must leave nothing
# behind in someone's prefix.
cleanup() {
    brew uninstall --formula "$TAP/tupperclaude" >/dev/null 2>&1 || true
    brew untap "$TAP" >/dev/null 2>&1 || true
    rm -rf "$work"
}
trap cleanup EXIT INT TERM

if brew tap | grep -qx "$TAP"; then
    echo "run-formula-test.sh: $TAP is already tapped — removing it first." >&2
    brew untap "$TAP" >/dev/null 2>&1 || true
fi

echo "=== packaging the working tree ==="
# git archive, so the tarball contains exactly what is tracked — the same thing
# a release tarball would contain. Untracked scratch files are excluded for
# free, which is the point.
tarball="$work/tupperclaude.tar.gz"
git -C "$root" archive --format=tar.gz --prefix=tupperclaude/ -o "$tarball" HEAD
sha=$(shasum -a 256 "$tarball" | awk '{print $1}')
echo "  $(wc -c <"$tarball" | tr -d ' ') bytes, sha256 $sha"

echo "=== rendering a local-source formula ==="
# Replace the head stanza with a file:// url + sha256. `brew install` refuses a
# head-only formula without --HEAD, and --HEAD would fetch the remote instead of
# this tree, which is the whole thing being avoided.
#
# `version` is explicit because Homebrew infers it from the URL's filename, and
# a file:// tarball in a temp directory has nothing version-shaped in its name —
# without this the install fails with "invalid attribute ... version (nil)".
local_formula="$work/tupperclaude.rb"
ver=$(cat "$root/.version")
sed "s|^  head .*|  url \"file://$tarball\"\n  version \"$ver\"\n  sha256 \"$sha\"|" \
    "$formula" >"$local_formula"
grep -q "^  url \"file://" "$local_formula" || {
    echo "failed to rewrite the source stanza — did 'head ...' change shape?" >&2
    exit 1
}

echo "=== creating a throwaway tap ==="
brew tap-new --no-git "$TAP" >/dev/null
tap_dir=$(brew --repository "$TAP")
mkdir -p "$tap_dir/Formula"
cp "$local_formula" "$tap_dir/Formula/tupperclaude.rb"
echo "  $tap_dir"

echo "=== brew audit ==="
# --strict catches the style problems that would make this unmergeable into a
# real tap. Not fatal: some audits assume a published, tagged formula, which
# this deliberately is not yet.
# Output is trimmed: auditing a formula in a --no-git tap makes brew 6 raise
# and print a 20-line Ruby backtrace, which would bury the install and test
# results that actually matter.
brew audit --formula --strict "$TAP/tupperclaude" 2>&1 | tail -3 || true

echo "=== brew install --build-from-source ==="
brew install --build-from-source --formula "$TAP/tupperclaude"

echo "=== brew test ==="
# No --formula here: `brew test` does not accept it (unlike install/uninstall).
brew test "$TAP/tupperclaude"

echo "=== brew uninstall + untap ==="
brew uninstall --formula "$TAP/tupperclaude"
brew untap "$TAP"

echo ""
echo "formula OK: packaged, installed, tested and removed cleanly."

#!/bin/sh
# install-case.sh — runs INSIDE the container. Installs tupperclaude the way
# $VARIATION says, then asserts the same contract for every variation:
# commands defined, completion bound, --version works, and the wizard refuses
# a non-TTY cleanly instead of silently taking every default.
#
# The repo is at /src, read-only. It is COPIED into place rather than used from
# the mount, because a real install is a copy and because $ZSH_CUSTOM must be
# writable.

set -eu

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq zsh git ca-certificates jq >/dev/null 2>&1

: "${VARIATION:?VARIATION not set}"

install_omz() {
    git clone -q --depth 1 https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh"
    cp "$HOME/.oh-my-zsh/templates/zshrc.zsh-template" "$HOME/.zshrc"
}

# The plugin, copied to wherever this variation wants it.
place_plugin() {
    mkdir -p "$1"
    cp -a /src/. "$1/"
    rm -rf "$1/.git"
}

case "$VARIATION" in
    omz-plugin)
        # The documented install (INSTALL.md): clone into $ZSH_CUSTOM/plugins
        # and add to plugins=(). omz runs compinit BEFORE sourcing the plugin.
        install_omz
        place_plugin "$HOME/.oh-my-zsh/custom/plugins/tupperclaude"
        sed -i 's/^plugins=(git)$/plugins=(git tupperclaude)/' "$HOME/.zshrc"
        grep -q 'plugins=(git tupperclaude)' "$HOME/.zshrc"
        ;;
    omz-manual-source)
        # oh-my-zsh present, but the plugin sourced by hand AFTER the omz line
        # — so compinit has also already run, by a different route.
        install_omz
        place_plugin "$HOME/tupperclaude"
        echo 'source $HOME/tupperclaude/tupperclaude.plugin.zsh' >> "$HOME/.zshrc"
        ;;
    plain-source-then-compinit)
        # INSTALL.md "manual" path, no oh-my-zsh: plugin first, compinit after.
        place_plugin "$HOME/tupperclaude"
        printf '%s\n' \
            'source $HOME/tupperclaude/tupperclaude.plugin.zsh' \
            'autoload -Uz compinit' \
            'compinit -u -d $HOME/.zcompdump' \
            > "$HOME/.zshrc"
        ;;
    plain-compinit-then-source)
        # The same, ordered the other way — the trap the omz bug came from.
        place_plugin "$HOME/tupperclaude"
        printf '%s\n' \
            'autoload -Uz compinit' \
            'compinit -u -d $HOME/.zcompdump' \
            'source $HOME/tupperclaude/tupperclaude.plugin.zsh' \
            > "$HOME/.zshrc"
        ;;
    *)
        echo "install-case.sh: unknown VARIATION '$VARIATION'" >&2
        exit 2
        ;;
esac

fail=0
report() { # report <ok|FAIL> <description> [detail]
    printf '  %-4s %s\n' "$1" "$2"
    [ $# -gt 2 ] && printf '       %s\n' "$3"
    [ "$1" = FAIL ] && fail=1
    return 0
}

# --- the shell starts at all -------------------------------------------------
# Startup errors are the thing under test, so stderr is deliberately kept.
if out=$(zsh -i -c 'print startup-ok' 2>&1) && [ "$out" = startup-ok ]; then
    report ok "interactive shell starts clean"
else
    report FAIL "interactive shell starts clean" "$out"
fi

# --- every public command is defined ----------------------------------------
missing=$(zsh -i -c '
    for f in $_tupperclaude_commands; do
        (( ${+functions[$f]} )) || print -r -- $f
    done' 2>/dev/null)
if [ -z "$missing" ]; then
    report ok "every public command is defined"
else
    report FAIL "every public command is defined" "missing: $(echo $missing)"
fi

# --- the completion is bound -------------------------------------------------
# The regression this whole file exists for.
unbound=$(zsh -i -c '
    for f in $_tupperclaude_commands; do
        [[ ${_comps[$f]:-} == _claude-docker ]] || print -r -- $f
    done' 2>/dev/null)
if [ -z "$unbound" ]; then
    report ok "completion bound for every command"
else
    report FAIL "completion bound for every command" "unbound: $(echo $unbound)"
fi

# --- --version works through the install ------------------------------------
if ver=$(zsh -i -c 'claude-docker-status --version' 2>&1) && \
   echo "$ver" | grep -q '^tupperclaude '; then
    report ok "claude-docker-status --version" "$ver"
else
    report FAIL "claude-docker-status --version" "$ver"
fi

# --- --help works for every command without a TTY ---------------------------
# Help must never need a terminal: it is what a user reaches for from a script
# or a pager. A command that hangs or errors here is broken.
badhelp=$(zsh -i -c '
    for f in $_tupperclaude_commands; do
        $f --help >/dev/null 2>&1 </dev/null || print -r -- $f
    done' 2>/dev/null)
if [ -z "$badhelp" ]; then
    report ok "--help works for every command, no TTY"
else
    report FAIL "--help works for every command, no TTY" "failed: $(echo $badhelp)"
fi

# --- the wizard refuses a non-TTY rather than answering itself --------------
if zsh -i -c claude-docker-configure </dev/null >/tmp/wiz 2>&1; then
    report FAIL "wizard refuses without a TTY" "returned 0: $(head -1 /tmp/wiz)"
elif grep -q 'interactive terminal' /tmp/wiz; then
    report ok "wizard refuses without a TTY"
else
    report FAIL "wizard refuses without a TTY" "wrong error: $(head -1 /tmp/wiz)"
fi

# --- nothing above wrote into the working directory -------------------------
# Loading a plugin, printing help and being refused a TTY must all be inert.
# Checked against the container's own copy, not /src: /src is mounted read-only,
# so asserting there proves nothing about this run — it only re-reports whatever
# the host checkout already contained. (The runner checks that separately,
# before spending minutes on containers.)
stray=$(find "$HOME" -maxdepth 3 -name MACHINE.md 2>/dev/null)
if [ -z "$stray" ]; then
    report ok "no MACHINE.md written by loading/--help/configure"
else
    report FAIL "no MACHINE.md written by loading/--help/configure" "$stray"
fi

exit $fail

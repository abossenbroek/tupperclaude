#!/bin/sh
# run-install-matrix.sh — install tupperclaude the way users actually install
# it, in a throwaway Linux container, once per documented variation.
#
# The zsh suite sources the plugin by absolute path under `zsh -f`, which never
# starts a login shell, never reads a .zshrc and never touches the completion
# system. That blind spot hid a real bug: oh-my-zsh runs compinit BEFORE it
# sources a plugin, so the $fpath prepend landed too late and no command
# completed anything on the primary documented install path. Nothing in the
# suite could have caught it. This is the test that can.
#
# Each variation gets its own `docker run --rm` — one contaminated $HOME must
# not be able to affect the next — and the containers are discarded either way.
#
# Usage: zsh/tests/docker/run-install-matrix.sh [variation ...]
#        (no arguments = every variation)

set -eu

IMAGE=${TUPPERCLAUDE_TEST_IMAGE:-debian:bookworm-slim}
root=$(cd "$(dirname "$0")/../../.." && pwd)
here=$(cd "$(dirname "$0")" && pwd)

ALL="omz-plugin omz-manual-source plain-source-then-compinit plain-compinit-then-source"
want=${*:-$ALL}

# A MACHINE.md in the checkout means someone ran a claude-docker command from
# the repo root — the file is written into $PWD and nothing removes it. Caught
# here, before minutes of container work, because it silently ends up inside
# every /src copy below and makes the per-case assertion unreadable.
if [ -e "$root/MACHINE.md" ]; then
    echo "run-install-matrix.sh: $root/MACHINE.md exists — the checkout is polluted." >&2
    echo "  a claude-docker command was run from the repo root; nothing cleans this up." >&2
    echo "  rm $root/MACHINE.md" >&2
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    echo "run-install-matrix.sh: no reachable Docker daemon." >&2
    echo "  start Docker Desktop, or run 'make check' for the fast gate." >&2
    exit 1
fi

pass=0
fail=0
failed=''

for variation in $want; do
    case " $ALL " in
        *" $variation "*) ;;
        *) echo "unknown variation '$variation' (have: $ALL)" >&2; exit 2 ;;
    esac

    echo "============================================================"
    echo "=== $variation ($IMAGE)"
    echo "============================================================"

    # /src read-only: nothing in the container can write back to the checkout.
    if docker run --rm \
        -e VARIATION="$variation" \
        -v "$root:/src:ro" \
        -v "$here/install-case.sh:/install-case.sh:ro" \
        "$IMAGE" sh /install-case.sh
    then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        failed="$failed $variation"
    fi
    echo ""
done

echo "============================================================"
echo "install matrix: $pass passed, $fail failed"
[ -n "$failed" ] && echo "failed:$failed"
echo "============================================================"

[ "$fail" -eq 0 ]

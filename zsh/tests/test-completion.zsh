#!/usr/bin/env zsh
# test-completion.zsh — the completion is actually BOUND, in both compinit
# orderings.
#
# Every other test in this suite sources the plugin and calls functions
# directly, which never touches the completion system at all. That blind spot
# hid a real bug: oh-my-zsh adds a plugin's ROOT directory to $fpath, runs
# compinit, and only then sources <plugin>.plugin.zsh — so the $fpath prepend
# in zsh/tupperclaude.zsh lands after compinit has already scanned, and
# zsh/completions/ is a subdirectory omz's root-only convention never looks in.
# `claude-docker-arm<TAB>` completed nothing, in every shell, for the primary
# documented install path, and nothing here noticed.
#
# Each ordering runs in its own `zsh -f` child, because compinit is a
# once-per-shell operation: asserting both orderings from one shell would mean
# the second assertion inherits the first one's $_comps and proves nothing.

emulate -L zsh
setopt local_options noksharrays

source $TC_TEST_LIB
source $TUPPERCLAUDE_TEST_ROOT/tupperclaude.plugin.zsh

cd -- $TC_TEST_WORKDIR || exit 1

# The expected binding: every public command completes via the one dispatching
# completion function, named after the file in zsh/completions/.
local -r want=_claude-docker

# ============================================================================
# Helper: run a child shell in a given ordering and report what got bound
# ============================================================================

# comps_in <name> <line-before-source> ... — writes a child script that runs
# the given setup lines, sources the plugin, and prints "<command>=<binding>"
# for each public command. Returns the child's output in $reply.
#
# $HOME is the per-case mktemp -d the harness provides, so each compdump this
# writes is thrown away with it.
comps_in() {
    local name=$1; shift
    local child="$TC_TEST_WORKDIR/comp-child-$name.zsh"
    print -r -l -- \
        '#!/usr/bin/env zsh' \
        "$@" \
        'for c in $_tupperclaude_commands; do' \
        '    print -r -- "$c=${_comps[$c]:-<none>}"' \
        'done' \
        >$child
    reply=("${(@f)$(zsh -f $child 2>&1)}")
}

# check_all_bound <label> — every line of $reply must be "<cmd>=_claude-docker".
# Reports the first offender rather than one not_ok per command: fifteen
# identical failures are one failure.
check_all_bound() {
    local label=$1 line bad=''
    integer n=0
    for line in $reply; do
        [[ -z $line ]] && continue
        (( n++ ))
        [[ $line == *"=$want" ]] || { bad=$line; break }
    done
    if [[ -n $bad ]]; then
        not_ok "$label" "expected every command to complete via $want" "first mismatch: $bad"
    elif (( n != $#_tupperclaude_commands )); then
        not_ok "$label" "expected $#_tupperclaude_commands bindings, saw $n" "output: ${reply[*]}"
    else
        ok "$label ($n commands)"
    fi
}

# ============================================================================
# 1. oh-my-zsh ordering: compinit FIRST, plugin sourced afterwards
# ============================================================================
# This is the case that was broken. Without the compdef call in
# zsh/tupperclaude.zsh every command here comes back <none>.

comps_in omz \
    'autoload -Uz compinit' \
    'compinit -u -d $HOME/.zcompdump-omz' \
    'source $TUPPERCLAUDE_TEST_ROOT/tupperclaude.plugin.zsh'
check_all_bound "omz ordering (compinit before the plugin) binds the completion"

# ============================================================================
# 2. Manual ordering: plugin sourced FIRST, compinit afterwards
# ============================================================================
# The INSTALL.md "manual" path. Here compdef does not exist yet when the plugin
# loads, so the binding must come from compinit finding the file on $fpath —
# i.e. this asserts the compdef call did not become load-bearing for an
# ordering that never needed it.

comps_in manual \
    'source $TUPPERCLAUDE_TEST_ROOT/tupperclaude.plugin.zsh' \
    'autoload -Uz compinit' \
    'compinit -u -d $HOME/.zcompdump-manual'
check_all_bound "manual ordering (plugin before compinit) binds the completion"

# ============================================================================
# 3. The two command lists cannot drift apart
# ============================================================================
# $_tupperclaude_commands drives both the autoload and the compdef; the
# `#compdef` line drives the manual ordering. A command added to one and not
# the other loses its completion in exactly one install path — the failure mode
# that is hardest to notice by hand, so it is asserted here instead.

local -r compfile="$TUPPERCLAUDE_ZSH_DIR/completions/_claude-docker"
[[ -r $compfile ]]
check "the completion file is where the plugin expects it" $? "$compfile"

# First line is "#compdef cmd cmd cmd ..."; drop the directive, keep the names.
# The pattern is quoted, not backslash-escaped: inside ${name#pattern} a bare \#
# is not an escape for a literal '#', and the strip silently does nothing.
local first
first="$(command head -1 $compfile)"
local -a declared
declared=(${(o)${=first#'#compdef'}})
local -a registered
registered=(${(o)_tupperclaude_commands})

[[ "$declared" == "$registered" ]]
check "#compdef list matches \$_tupperclaude_commands" $? \
    "#compdef: $declared" \
    "plugin:   $registered"

test_summary

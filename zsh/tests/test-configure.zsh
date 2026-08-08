#!/usr/bin/env zsh
# test-configure.zsh — claude-docker-configure, the first thing a new user
# runs and, until this file existed, the only command with no assertions at all
# AND a shipping bug that made it useless: it read answers with `read -k 1`,
# which returns after exactly one character and leaves the trailing newline in
# the input buffer, where the NEXT prompt consumed it, matched no case and
# silently fell through to its default. Typing "2<Enter>" answered one question
# and destroyed the next — so every answer after the first was discarded and the
# generated config never reflected what the user typed.
#
# No assertion about a wizard's OUTPUT can catch that; only driving it through a
# real terminal and reading the file it wrote can. So every case here runs the
# wizard on a pty (`script`), types a full set of answers, and asserts the
# generated ~/.tupperclaude.zsh reflects the LAST answer as well as the first.
#
# SAFETY: every run gets its own throwaway $HOME under $TC_TEST_WORKDIR. The
# real ~/.tupperclaude.zsh and ~/.zshrc are never read or written — the child
# process is given a different $HOME entirely, and the assertions below check
# only inside it.

emulate -L zsh
setopt local_options noksharrays

source $TC_TEST_LIB
source $TUPPERCLAUDE_TEST_ROOT/tupperclaude.plugin.zsh

cd -- $TC_TEST_WORKDIR || exit 1

local out='' rc=0 cfg='' wizhome=''
# Which child pty_wizard runs. Empty means the default one defined below; the
# $TUPPERCLAUDE_DIR cases point it at a child that never sources the plugin.
local wiz_child=''
integer wiz_n=0

require_fn claude-docker-configure || { test_summary; return }

if (( ! ${+commands[script]} )); then
    not_ok "the 'script' utility is available" \
        "claude-docker-configure demands a TTY by design; without script(1) there is" \
        "no way to drive it, and this whole file is skipped"
    test_summary
    return
fi

# The child the pty runs: source the plugin, run the wizard, nothing else.
local -r child="$TC_TEST_WORKDIR/wizard-child.zsh"
print -r -l -- \
    '#!/usr/bin/env zsh' \
    'source $TUPPERCLAUDE_TEST_ROOT/tupperclaude.plugin.zsh' \
    'claude-docker-configure "$@"' \
    >$child

# Two more children that do NOT source the plugin shim: $fpath plus autoload and
# nothing else, which is how a colleague wires this up when they have the repo
# but have not read the install instructions — and the only setup in which
# $TUPPERCLAUDE_DIR is not set. `unset` rather than merely not setting it,
# because the variable is exported by whatever ran the suite.
local -r child_noshim="$TC_TEST_WORKDIR/wizard-child-noshim.zsh"
print -r -l -- \
    '#!/usr/bin/env zsh' \
    'fpath=($TUPPERCLAUDE_TEST_ROOT/zsh/functions $fpath)' \
    'autoload -Uz $TUPPERCLAUDE_TEST_ROOT/zsh/functions/*(:t)' \
    'unset TUPPERCLAUDE_DIR' \
    'claude-docker-configure "$@"' \
    >$child_noshim

# The same, but with $TUPPERCLAUDE_DIR pointing at a checkout that is not there
# — a stale export in someone's .zshrc after moving the repo.
local -r child_baddir="$TC_TEST_WORKDIR/wizard-child-baddir.zsh"
print -r -l -- \
    '#!/usr/bin/env zsh' \
    'fpath=($TUPPERCLAUDE_TEST_ROOT/zsh/functions $fpath)' \
    'autoload -Uz $TUPPERCLAUDE_TEST_ROOT/zsh/functions/*(:t)' \
    'export TUPPERCLAUDE_DIR=/tupperclaude-no-such-checkout' \
    'claude-docker-configure "$@"' \
    >$child_baddir

# pty_wizard <home> <answers> [args...] — run the wizard on a pty with $HOME
# set to <home>, typing <answers>. Prints the transcript path on stdout.
#
# Two portability traps, both of which produce a wizard that silently answers
# nothing rather than an obvious failure:
#
#  1. script(1)'s command syntax differs between the platforms this suite runs
#     on. BSD/macOS takes `script [file] [command ...]`; util-linux takes
#     `script -c <command> [file]`. Getting it wrong records the shell's own
#     session instead of the wizard's.
#
#  2. The answers must not simply be piped in and the pipe closed. macOS's
#     script(1) forwards the EOF to the pty ahead of the buffered text, the
#     line discipline hands the child a zero-length read, and the wizard's
#     FIRST `read` returns empty — every answer shifts by one question and
#     these assertions would be testing nonsense (which is exactly how this
#     harness was caught mis-reporting a working wizard as broken). Holding
#     the write end open past the last read fixes it; a fifo does NOT, because
#     macOS script tcgetattr()s its own stdin and refuses a non-tty fifo
#     outright ("Operation not supported on socket").
#
#     So: a brace group that writes the answers and then sleeps. The sleep is
#     what keeps the pipe open; the child normally finishes well inside it.
#
# The watchdog is not optional either: a wizard that grows a question this
# file does not answer would otherwise block the whole suite forever.
pty_wizard() {
    local home=$1 answers=$2
    shift 2
    local transcript="$TC_TEST_WORKDIR/wizard-out-$wiz_n.txt"

    # Trailing newlines are harmless — nothing reads them — and they keep a
    # wizard that asks one extra optional question from blocking.
    {
        if [[ "$(command uname -s)" == Darwin ]]; then
            { print -rn -- "$answers"$'\n\n\n\n'; sleep 2 } | \
                HOME=$home command script -q /dev/null zsh -f ${wiz_child:-$child} "$@" >$transcript 2>&1
        else
            { print -rn -- "$answers"$'\n\n\n\n'; sleep 2 } | \
                HOME=$home command script -q -c "zsh -f ${wiz_child:-$child} $*" /dev/null >$transcript 2>&1
        fi
    } &
    local spid=$!
    integer waited=0
    while kill -0 $spid 2>/dev/null && (( waited < 40 )); do
        sleep 0.5
        (( waited++ ))
    done
    kill -9 $spid 2>/dev/null
    wait $spid 2>/dev/null
    rc=$?
    print -r -- "$transcript"
}

# run_wizard <answers> — types <answers> at the wizard on a pty, in a FRESH
# throwaway $HOME, and leaves the transcript in $out, the generated config in
# $cfg and the home in $wizhome.
run_wizard() {
    local answers=$1
    (( wiz_n++ ))
    wizhome="$TC_TEST_WORKDIR/wizhome-$wiz_n"
    command mkdir -p "$wizhome"
    # A valid ~/.claude.json so the preflight table reports ok rather than FAIL;
    # a failing preflight changes the closing text but not the questions.
    print -r -- '{}' >"$wizhome/.claude.json"

    local transcript
    transcript="$(pty_wizard "$wizhome" "$answers")"
    out="$(<$transcript)"
    cfg=''
    [[ -f "$wizhome/.tupperclaude.zsh" ]] && cfg="$(<"$wizhome/.tupperclaude.zsh")"
    return 0
}

export TS_AUTHKEY=tskey-auth-fake
unset FAKE_DOCKER_IMAGES

# ============================================================================
# the pty harness itself works
# ============================================================================

run_wizard $'1\n3\nn\n'
[[ $out == *'setup wizard'* ]]
check "wizard: runs on a pty and prints its banner" $? "transcript: $out"
[[ $out != *'not interactive'* && $out != *"can't open terminal"* ]]
check "wizard: the pty satisfies its TTY guard" $? "transcript: $out"
[[ -n $cfg ]]
check "wizard: wrote ~/.tupperclaude.zsh in the throwaway HOME" $? "home: $wizhome"

# ============================================================================
# THE BUG: every answer after the first must survive
# ============================================================================
#
# network=default (question 1), aws=yes (the LAST question). Under the old
# single-keypress reads, the newline after "2" was consumed by the aws prompt,
# which then matched no case and took its default of "no" — so a config with
# aws off here means the bug is back.

run_wizard $'2\ny\n'
[[ $cfg == *"zstyle ':omz:plugins:tupperclaude' network 'default'"* ]]
check "wizard: the FIRST answer (network=default) is recorded" $? "config: $cfg"
[[ $cfg == *"zstyle ':omz:plugins:tupperclaude' aws 'on'"* ]]
check "wizard: the LAST answer (aws=yes) is recorded — not silently discarded" $? \
    "config: $cfg"

# The same shape with the answers swapped, so a config that merely happens to
# contain both values cannot pass by accident.
run_wizard $'1\n3\nn\n'
[[ $cfg == *"zstyle ':omz:plugins:tupperclaude' network 'tailscale'"* ]]
check "wizard: network=tailscale is recorded" $? "config: $cfg"
[[ $cfg != *"aws 'on'"* ]]
check "wizard: aws stays off when the last answer is 'n'" $? "config: $cfg"

# ============================================================================
# a full four-answer run, including a free-text answer
# ============================================================================
#
# network=tailscale, auth=1Password, the reference typed as free text, aws=yes.
# The op-ref is the answer most exposed to a read bug: it is the only one that
# is not a single character, and it contains slashes and colons.

run_wizard $'1\n1\nop://Private/Tailscale Key/authkey\ny\n'
[[ $cfg == *"network 'tailscale'"* ]]
check "wizard/full: answer 1 (network) recorded" $? "config: $cfg"
[[ $cfg == *"op-ref 'op://Private/Tailscale Key/authkey'"* ]]
check "wizard/full: answer 3 (a free-text 1Password reference) recorded verbatim" $? \
    "config: $cfg"
[[ $cfg == *"aws 'on'"* ]]
check "wizard/full: answer 4 (aws) recorded" $? "config: $cfg"

# The generated file must be valid zsh and must actually take effect when
# sourced — a config that parses but sets nothing is the same failure wearing a
# different hat.
zsh -n "$wizhome/.tupperclaude.zsh"
check "wizard: the generated config passes zsh -n" $?

local resolved
resolved="$(zsh -f -c "source $wizhome/.tupperclaude.zsh; zstyle -s ':omz:plugins:tupperclaude' op-ref v; print -r -- \$v")"
[[ $resolved == 'op://Private/Tailscale Key/authkey' ]]
check "wizard: sourcing the generated config really sets the zstyle" $? "got: $resolved"

# And the answers are echoed back so the user can see what was recorded.
[[ $out == *'-> network = tailscale'* ]]
check "wizard: echoes each answer back" $? "transcript: $out"

# ============================================================================
# a 1Password reference containing shell metacharacters
# ============================================================================
#
# The value is interpolated into a SINGLE-QUOTED zstyle line, so a ' in it used
# to close that quote early and hand the user a config that failed the wizard's
# own `zsh -n` gate — with a "this is a bug in claude-docker-configure" message
# and no config at all. `op://Ada's Vault/Tailscale/authkey` is an ordinary
# 1Password vault name, so this was reachable by an ordinary user.
#
# Round-tripping is the real assertion: an escape that yields valid zsh but the
# wrong value is worse than the syntax error it replaced. So each case below
# sources the generated file and compares the zstyle against the typed string.

# quote_case <description> <op-ref value>
quote_case() {
    local desc=$1 value=$2
    run_wizard $'1\n1\n'"$value"$'\ny\n'

    [[ -n $cfg ]]
    check "wizard/$desc: a config was written at all" $? "home: $wizhome"

    zsh -n "$wizhome/.tupperclaude.zsh"
    check "wizard/$desc: the generated config passes zsh -n" $? "config: $cfg"

    local got
    got="$(zsh -f -c "source $wizhome/.tupperclaude.zsh; zstyle -s ':omz:plugins:tupperclaude' op-ref v; print -rn -- \$v")"
    [[ $got == "$value" ]]
    check "wizard/$desc: the op-ref round-trips to the exact typed value" $? \
        "want: $value" "got:  $got"
}

quote_case single-quote "op://Ada's Vault/Tailscale/authkey"
quote_case backslash 'op://Back\slash Vault/Tailscale/authkey'
quote_case ampersand 'op://A&B Vault/Tailscale/authkey'
quote_case quote-backslash-ampersand "op://Ada's A&B\\Vault/Tailscale/authkey"

# ============================================================================
# $TUPPERCLAUDE_DIR is set by the plugin shim — the wizard must not need it
# ============================================================================
#
# claude-docker-configure is autoloadable on its own, and the colleague who
# points $fpath at zsh/functions without sourcing zsh/tupperclaude.zsh is the
# common first-contact case. With $TUPPERCLAUDE_DIR unset the template path
# collapsed to the absolute "/zsh/templates/tupperclaude.zsh" — and, because the
# check sat in section 3, only AFTER every question had been asked and answered.
# The user lost their answers to an error naming a path at the filesystem root
# and blaming their installation.
#
# $0 in an autoloaded function is the function NAME, so the fallback goes
# through $functions_source, as _claude_docker_ctx does.

wiz_child=$child_noshim
run_wizard $'1\n1\nop://Ada Vault/Tailscale/authkey\ny\n'
wiz_child=''

[[ -n $cfg ]]
check "wizard/no-shim: writes a config with \$TUPPERCLAUDE_DIR unset" $? \
    "transcript: $out"
[[ $out != *'/zsh/templates/tupperclaude.zsh'* ]]
check "wizard/no-shim: no 'template not found' — the directory is resolved, not assumed" $? \
    "transcript: $out"
[[ $cfg == *"op-ref 'op://Ada Vault/Tailscale/authkey'"* ]]
check "wizard/no-shim: the answers still reach the generated config" $? "config: $cfg"

# A $TUPPERCLAUDE_DIR that resolves but points nowhere: $functions_source is not
# a guarantee either (under `zsh -c` it is the bare string "zsh"), so the failure
# that matters is a plausible-looking wrong directory. It must name the variable
# — "check your installation" is true and useless when the installation is fine
# and a stale export is at fault.
wiz_child=$child_baddir
run_wizard $'1\n3\nn\n'
wiz_child=''

[[ -z $cfg ]]
check "wizard/bad-dir: an unresolvable TUPPERCLAUDE_DIR writes no config" $? "config: $cfg"
[[ $out == *TUPPERCLAUDE_DIR* ]]
check "wizard/bad-dir: the error names TUPPERCLAUDE_DIR as the fix" $? "transcript: $out"
[[ $out == *'/tupperclaude-no-such-checkout'* ]]
check "wizard/bad-dir: the error names the directory it resolved" $? "transcript: $out"
# And it gives up BEFORE collecting answers it is going to throw away.
[[ $out != *'Network —'* ]]
check "wizard/bad-dir: fails before asking the first question, not after the last" $? \
    "transcript: $out"

# ============================================================================
# defaults, and unrecognised input
# ============================================================================

# Enter alone at every prompt: tailscale, skip, no aws.
run_wizard $'\n\n\n'
[[ $cfg == *"network 'tailscale'"* ]]
check "wizard/defaults: bare Enter takes the documented default" $? "config: $cfg"
[[ $cfg != *$'\n'"zstyle ':omz:plugins:tupperclaude' op-ref"* ]]
check "wizard/defaults: skipping the auth key leaves op-ref commented out" $? "config: $cfg"
[[ $out == *TS_AUTHKEY* ]]
check "wizard/defaults: warns that tailscale without a key cannot come up" $? \
    "transcript: $out"

# An unrecognised answer must say so and fall back, not silently proceed.
run_wizard $'banana\nq\nmaybe\n'
[[ $out == *unrecognised* ]]
check "wizard: an unrecognised answer is called out, not silently defaulted" $? \
    "transcript: $out"
[[ $cfg == *"network 'tailscale'"* ]]
check "wizard: an unrecognised answer falls back to the default" $? "config: $cfg"

# ============================================================================
# the op-ref answer left empty
# ============================================================================

run_wizard $'1\n1\n\nn\n'
[[ $out == *'no reference given'* ]]
check "wizard: an empty 1Password reference is reported" $? "transcript: $out"
# The template's op-ref line must still be COMMENTED OUT. Matching on
# "op-ref 'op://" alone is not enough — the commented example in the template
# contains exactly that text, so the assertion has to be anchored to the start
# of an uncommented line.
[[ $cfg != *$'\n'"zstyle ':omz:plugins:tupperclaude' op-ref"* ]]
check "wizard: an empty 1Password reference leaves op-ref commented out" $? "config: $cfg"

# ============================================================================
# ~/.zshrc handling
# ============================================================================

run_wizard $'1\n3\nn\n'
local zshrc="$wizhome/.zshrc"
[[ ! -f $zshrc ]]
check "wizard: no ~/.zshrc is created where none existed" $?
[[ $out == *'source ~/.tupperclaude.zsh'* ]]
check "wizard: tells the user the source line to add themselves" $? "transcript: $out"

# With a ~/.zshrc present the wizard asks; answering Y appends exactly one line.
(( wiz_n++ ))
wizhome="$TC_TEST_WORKDIR/wizhome-$wiz_n"
command mkdir -p "$wizhome"
print -r -- '{}' >"$wizhome/.claude.json"
print -r -l -- '# my zshrc' 'export FOO=bar' >"$wizhome/.zshrc"
local before="$(<"$wizhome/.zshrc")"
pty_wizard "$wizhome" $'1\n3\nn\nY' >/dev/null
local after="$(<"$wizhome/.zshrc")"
[[ $after == "$before"*'source ~/.tupperclaude.zsh'* ]]
check "wizard: appends the source line to an existing ~/.zshrc, preserving it" $? \
    "after: $after"
[[ $after == *'export FOO=bar'* ]]
check "wizard: the user's existing ~/.zshrc content is untouched" $? "after: $after"

# ============================================================================
# re-running backs up the previous config
# ============================================================================

run_wizard $'2\ny\n'
local first_cfg=$cfg
local reuse_home=$wizhome
# Second run in the SAME home, with different answers.
(( wiz_n++ ))
pty_wizard "$reuse_home" $'1\n3\nn' >/dev/null
local -a backups=("$reuse_home"/.tupperclaude.zsh.bak-*(N))
(( ${#backups} == 1 ))
check "wizard: re-running backs up the previous config" $? "found: ${backups[*]}"
if (( ${#backups} == 1 )); then
    [[ "$(<$backups[1])" == "$first_cfg" ]]
    check "wizard: the backup is the previous config, byte for byte" $?
fi
[[ "$(<"$reuse_home/.tupperclaude.zsh")" == *"network 'tailscale'"* ]]
check "wizard: the second run's answers replace the first's" $?

# ============================================================================
# -h/--help works WITHOUT a terminal, and writes nothing
# ============================================================================
#
# The TTY guard is deliberately after the help handling: `claude-docker-configure
# -h` must work from a script, a pipe or a pager.

(( wiz_n++ ))
wizhome="$TC_TEST_WORKDIR/wizhome-$wiz_n"
command mkdir -p "$wizhome"
out="$(HOME=$wizhome zsh -f $child --help 2>&1 </dev/null)"
rc=$?
(( rc == 0 ))
check "wizard --help: exits 0 with no terminal at all" $? "rc=$rc" "$out"
[[ $out == *wizard* ]]
check "wizard --help: describes what the command does" $? "got: $out"
[[ ! -e "$wizhome/.tupperclaude.zsh" ]]
check "wizard --help: writes no config file" $?

# --version, likewise before the TTY guard: reflexively typed, and an error
# telling you to go run a different command is a worse answer than the version.
out="$(HOME=$wizhome zsh -f $child --version 2>&1 </dev/null)"
rc=$?
(( rc == 0 ))
check "wizard --version: exits 0 with no terminal at all" $? "rc=$rc" "$out"
[[ $out == *tupperclaude* ]]
check "wizard --version: names the version" $? "got: $out"
[[ ! -e "$wizhome/.tupperclaude.zsh" ]]
check "wizard --version: writes no config file" $?

# And without --help, no terminal must be a clean refusal rather than a config
# full of silently-defaulted answers.
out="$(HOME=$wizhome zsh -f $child 2>&1 </dev/null)"
rc=$?
(( rc != 0 ))
check "wizard: refuses cleanly when stdin is not a terminal" $? "rc=$rc"
[[ $out == *'tupperclaude: error:'* ]]
check "wizard: the no-terminal refusal uses the house error style" $? "got: $out"
[[ $out == *zstyle* ]]
check "wizard: the refusal names the non-interactive alternative" $? "got: $out"
[[ ! -e "$wizhome/.tupperclaude.zsh" ]]
check "wizard: the no-terminal refusal writes no config file" $?

# ============================================================================
# an unknown argument
# ============================================================================

out="$(HOME=$wizhome zsh -f $child --nope 2>&1 </dev/null)"
rc=$?
(( rc != 0 ))
check "wizard: an unknown argument returns non-zero" $? "rc=$rc"
[[ $out == *'tupperclaude: error:'* ]]
check "wizard: an unknown argument uses the house error style" $? "got: $out"

# ============================================================================
# every optional tool is asked about, and every answer lands in the config
# ============================================================================
#
# The tool questions are generated from $_tupperclaude_tools. Adding a tool to
# that array without a matching stanza in the template would ask the question
# and then drop the answer on the floor — the config is written by uncommenting
# a template line that has to exist. This asserts the whole array round-trips.
#
# Last in the file on purpose: every run_wizard above leaves $cfg behind for the
# assertions that follow it, so a run inserted mid-file answers a later test's
# question with the wrong config.
#
# ${(pl:...::y\n:)} repeats the answer once per tool without a command
# substitution — $(...) strips the trailing newline, which leaves the final
# answer unterminated and unread.
local answers
answers="${(pl:$(( $#_tupperclaude_tools * 2 ))::y\n:)}"
run_wizard "2"$'\n'"$answers"
local tool
for tool in $_tupperclaude_tools; do
    [[ $cfg == *"zstyle ':omz:plugins:tupperclaude' $tool 'on'"* ]]
    check "wizard: answering yes to $tool writes its zstyle line" $? "config: $cfg"
done

# And answering no to all of them leaves every one out, so a template stanza
# uncommented unconditionally cannot pass the check above.
answers="${(pl:$(( $#_tupperclaude_tools * 2 ))::n\n:)}"
run_wizard "2"$'\n'"$answers"
for tool in $_tupperclaude_tools; do
    [[ $cfg != *"' $tool 'on'"* ]]
    check "wizard: answering no to $tool leaves it out of the config" $? "config: $cfg"
done

test_summary

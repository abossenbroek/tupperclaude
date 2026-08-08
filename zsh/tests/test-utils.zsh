#!/usr/bin/env zsh
# test-utils.zsh — the internals and read-only commands that had no assertions
# at all: _claude_docker_sed_i, _claude_docker_info, _claude_docker_err /
# _claude_docker_warn, _claude_ts_online, claude-docker-status and
# claude-docker-doctor.
#
# _claude_docker_sed_i exists solely to bridge BSD sed (macOS) and GNU sed, and
# was previously only ever run against GNU sed in CI and BSD sed on the
# developer's laptop — with nothing asserting either. It is tested here directly
# so the macOS leg of the CI matrix has something to disagree about.
#
# claude-docker-status and claude-docker-doctor are read-only by contract, so
# they can be driven for real against the fake docker; nothing here touches a
# daemon, a container, an image or a volume.

emulate -L zsh
setopt local_options noksharrays

source $TC_TEST_LIB
source $TUPPERCLAUDE_TEST_ROOT/tupperclaude.plugin.zsh

cd -- $TC_TEST_WORKDIR || exit 1

# Declared ONCE, here, and only ever assigned below. A bare `local out` (no
# `=`) re-declared later in the same scope, while it still holds a value, makes
# zsh echo "out=<value>" to stdout — its query-on-redeclare behaviour — which
# lands in the middle of the TAP stream.
local out='' err='' rc=0 hb=''
local -a reply=()

# ============================================================================
# _claude_docker_sed_i
# ============================================================================

if require_fn _claude_docker_sed_i; then
    local f="$TC_TEST_WORKDIR/sed-target.txt"

    print -r -- 'hello /opt/homebrew/bin/uvx world' >$f
    _claude_docker_sed_i 's#/opt/homebrew/bin/uvx#/usr/local/bin/uvx#g' "$f"
    check "sed_i: returns 0 on a successful substitution" $?
    [[ "$(<$f)" == 'hello /usr/local/bin/uvx world' ]]
    check "sed_i: substitution actually applied in place" $? "got: $(<$f)"

    # The whole reason this function exists: `sed -i` (GNU) and `sed -i ''`
    # (BSD) disagree about the backup argument, and the -i.SUFFIX spelling it
    # uses leaves a backup file behind unless it is cleaned up. A stray
    # .claude-docker-bak next to a user's config is the visible symptom.
    [[ ! -e "$f.claude-docker-bak" ]]
    check "sed_i: leaves no .claude-docker-bak behind" $?

    local -a strays=("$TC_TEST_WORKDIR"/*claude-docker-bak(N))
    (( ${#strays} == 0 ))
    check "sed_i: leaves no backup files anywhere in the work dir" $? "${strays[@]}"

    # Multi-line and repeated matches, since the real call sites rewrite whole
    # JSON documents.
    print -r -l -- 'a /opt/homebrew/bin/uv x' '/opt/homebrew/bin/uv' 'z' >$f
    _claude_docker_sed_i 's#/opt/homebrew/bin/uv#/usr/local/bin/uv#g' "$f"
    [[ "$(<$f)" != */opt/homebrew/* ]]
    check "sed_i: rewrites every occurrence across lines" $? "got: $(<$f)"

    # A path containing a '/' on the RIGHT of the expression — the call sites
    # use '#' as the delimiter for exactly this reason.
    print -r -- 'X' >$f
    _claude_docker_sed_i "s#X#$HOME/.claude#g" "$f"
    [[ "$(<$f)" == "$HOME/.claude" ]]
    check "sed_i: handles a replacement containing slashes" $? "got: $(<$f)"

    # Missing file is a no-op that must NOT fail: the build's config whitelist
    # calls this on files that may legitimately not have been copied.
    _claude_docker_sed_i 's#a#b#' "$TC_TEST_WORKDIR/definitely-not-here.json"
    check "sed_i: missing file is a silent no-op returning 0" $?

    # And it must not have created the file it was pointed at.
    [[ ! -e "$TC_TEST_WORKDIR/definitely-not-here.json" ]]
    check "sed_i: missing file is not created as a side effect" $?

    command rm -f -- "$f"
fi

# ============================================================================
# _claude_docker_info / _claude_docker_err / _claude_docker_warn
# ============================================================================

if require_fn _claude_docker_info; then
    out="$(_claude_docker_info 'doing a thing' 2>/dev/null)"
    check "info: returns 0" $?
    [[ $out == 'tupperclaude: doing a thing' ]]
    check "info: prints the house-style prefix on stdout" $? "got: $out"

    # It goes to stdout, not stderr — it is progress, not a diagnostic. Nothing
    # anywhere may print a bare `<function-name>: ...` prefix.
    err="$(_claude_docker_info 'doing a thing' 2>&1 1>/dev/null)"
    [[ -z $err ]]
    check "info: writes nothing to stderr" $? "stderr: $err"

    [[ $out != *claude-ts-ensure:* && $out != *claude-docker-*:* ]]
    check "info: prefix is 'tupperclaude:', never a function name" $? "got: $out"
fi

if require_fn _claude_docker_err; then
    err="$(_claude_docker_err 'it broke' 'do this' 'or this' 2>&1 1>/dev/null)"
    [[ $err == *'tupperclaude: error: it broke'* ]]
    check "err: house-style prefix on stderr" $? "got: $err"
    [[ $err == *'do this'* && $err == *'or this'* ]]
    check "err: every fix is printed" $? "got: $err"

    out="$(_claude_docker_err 'it broke' 'do this' 2>/dev/null)"
    [[ -z $out ]]
    check "err: writes nothing to stdout" $? "stdout: $out"

    _claude_docker_err 'it broke' 2>/dev/null
    (( $? != 0 ))
    check "err: returns non-zero so it can tail a && chain" $?
fi

if require_fn _claude_docker_warn; then
    err="$(_claude_docker_warn 'careful' 2>&1 1>/dev/null)"
    [[ $err == *tupperclaude:*careful* ]]
    check "warn: house-style prefix on stderr" $? "got: $err"
    [[ $err != *error* ]]
    check "warn: does not call itself an error" $? "got: $err"
fi

# ============================================================================
# _claude_ts_online
# ============================================================================
#
# Reachable at all only because the shim now honours `inspect -f`; before that
# it could never report a running container. Note the timeout argument is a
# poll count with a 1s sleep, so every negative case here uses 1.

if require_fn _claude_ts_online; then
    export FAKE_DOCKER_CONTAINERS='ts-node'
    export FAKE_DOCKER_TS_ONLINE=1

    _claude_ts_online ts-node 1
    check "ts_online: Running/true -> returns 0" $?

    export FAKE_DOCKER_TS_ONLINE=0
    _claude_ts_online ts-node 1
    (( $? != 0 ))
    check "ts_online: Starting/false -> returns non-zero" $?

    # The distinction the whole function exists for: a node that reports
    # BackendState=Running while Self.Online is false is NOT online. A sidecar
    # in that state keeps its 100.x address and resolves nothing.
    export FAKE_DOCKER_TS_ONLINE=running-but-offline
    _claude_ts_online ts-node 1
    (( $? != 0 ))
    check "ts_online: BackendState=Running alone is not enough" $?

    # Non-interactive callers (this suite, scripts, CI) must see no heartbeat
    # output at all — stderr is not a terminal here.
    export FAKE_DOCKER_TS_ONLINE=0
    hb="$(_claude_ts_online ts-node 1 2>&1 1>/dev/null)"
    [[ -z $hb ]]
    check "ts_online: prints nothing when stderr is not a terminal" $? "stderr: $hb"

    unset FAKE_DOCKER_TS_ONLINE
    unset FAKE_DOCKER_CONTAINERS
fi

# ============================================================================
# claude-docker-status
# ============================================================================

if require_fn claude-docker-status; then
    # --- nothing running ---
    export FAKE_DOCKER_PS_DB=''
    unset FAKE_DOCKER_PS
    : >$FAKE_DOCKER_LOG
    out="$(claude-docker-status 2>&1)"
    check "status: exits 0 when nothing is running" $?
    [[ $out == *'no sandboxes are running'* ]]
    check "status: says so plainly when nothing is running" $? "got: $out"

    # It must not have tried to inspect or exec anything.
    load_docker_log
    records_matching inspect
    (( ${#reply} == 0 ))
    check "status: probes no sidecar when nothing is running" $?

    # --- two sandboxes, one with an online sidecar, one with none ---
    #
    # The sidecar name is derived from the label, so the DB below must use the
    # same derivation _claude_docker_ctx does: every non-alphanumeric char of
    # the directory becomes '-'.
    local dir_a='/tmp/proj-a' dir_b='/tmp/proj-b'
    local node_a="claude-ts-${dir_a//[^A-Za-z0-9]/-}"

    export FAKE_DOCKER_PS_DB="\
sandbox-a|aaa111|running|Up 2 hours|2 hours|tupperclaude.dir=$dir_a,tupperclaude.arch=arm64,tupperclaude.variant=base;\
sandbox-b|bbb222|running|Up 5 minutes|5 minutes|tupperclaude.dir=$dir_b,tupperclaude.arch=amd64,tupperclaude.variant=playwright"
    export FAKE_DOCKER_CONTAINERS="$node_a"
    export FAKE_DOCKER_TS_ONLINE=1
    : >$FAKE_DOCKER_LOG

    out="$(claude-docker-status 2>&1)"
    check "status: exits 0 with sandboxes running" $?

    [[ $out == *DIRECTORY*ARCH*VARIANT*UPTIME*TAILNET* ]]
    check "status: prints a header row" $? "got: $out"
    [[ $out == *$dir_a* && $out == *$dir_b* ]]
    check "status: lists every running sandbox, across directories" $? "got: $out"
    [[ $out == *arm64*base* && $out == *amd64*playwright* ]]
    check "status: reports each sandbox's arch and variant" $? "got: $out"
    [[ $out == *online* ]]
    check "status: reports 'online' for a sandbox whose sidecar is up" $? "got: $out"
    [[ $out == *n/a* ]]
    check "status: reports 'n/a' where there is no sidecar (network=default)" $? "got: $out"

    # The filter it queries with is a contract with docker, not an internal
    # detail: `--filter label=tupperclaude.arch` is what stops it listing every
    # container on the machine.
    load_docker_log
    records_matching ps
    (( ${#reply} >= 1 ))
    check "status: called docker ps" $?
    if (( ${#reply} >= 1 )); then
        argv_has "$reply[1]" 'label=tupperclaude.arch'
        check "status: filters ps on the tupperclaude.arch label" $?
        argv_has "$reply[1]" '-a'
        (( $? != 0 ))
        check "status: does NOT pass -a (only running sandboxes)" $?
    fi

    # --- a sidecar that is up but offline ---
    export FAKE_DOCKER_TS_ONLINE=0
    out="$(claude-docker-status 2>&1)"
    [[ $out == *OFFLINE* ]]
    check "status: reports OFFLINE for a running-but-disconnected sidecar" $? "got: $out"

    # --- the idle-sidecar section must not contradict itself ---
    #
    # This section used to be headed "removable with claude-docker-clean" while
    # individual rows said "may be in use" two columns later. On a real machine
    # it listed two sidecars with 21+ hours of live work under a heading that
    # asserted they were safe to delete. status is where people look FIRST —
    # before clean's own preview, which gets this right — so status was the
    # weaker of the two commands on precisely the case that destroys work.
    #
    # A sidecar with no LABELLED sandbox is not a sidecar with no sandbox: a
    # fish-launched session runs inside its sidecar's network namespace, carries
    # no tupperclaude.arch label, and dies when the sidecar goes.
    export FAKE_DOCKER_PS_DB='claude-ts-q-legacy|q1|running|Up 21 hours|21 hours|;claude-ts--tmp-gone|g1|exited|Exited (0) 2 days ago|2 days|'
    unset FAKE_DOCKER_CONTAINERS
    out="$(claude-docker-status 2>&1)"

    [[ $out != *'removable with claude-docker-clean'* ]]
    check "status: the idle-sidecar heading no longer asserts removability" $? "got: $out"
    [[ $out == *'no LABELLED sandbox'* ]]
    check "status: the heading says these have no LABELLED sandbox" $? "got: $out"

    local live_row dead_row
    live_row="$(print -r -- "$out" | command grep -- claude-ts-q-legacy)"
    dead_row="$(print -r -- "$out" | command grep -- claude-ts--tmp-gone)"

    [[ $live_row == *RUNNING* ]]
    check "status: a running idle sidecar is marked RUNNING, as clean marks it" $? "got: $live_row"
    [[ $live_row == *'legacy fish sidecar'* ]]
    check "status: a legacy-scheme sidecar is still flagged as such" $? "got: $live_row"
    [[ $dead_row != *RUNNING* ]]
    check "status: a stopped sidecar is NOT marked RUNNING" $? "got: $dead_row"

    unset FAKE_DOCKER_PS_DB FAKE_DOCKER_CONTAINERS FAKE_DOCKER_TS_ONLINE

    # --- --version is answered, not rejected ---
    out="$(claude-docker-status --version 2>&1)"
    check "status --version: exits 0" $?
    [[ $out == *tupperclaude* ]]
    check "status --version: names the version" $? "got: $out"
fi

# ============================================================================
# claude-docker-doctor
# ============================================================================
#
# doctor is pure diagnosis — it must never mutate anything — and its exit
# status is the contract: non-zero only when a REQUIRED check fails. A missing
# foreign-arch or playwright image is informational; treating those as failures
# made doctor exit non-zero on a completely healthy setup.

if require_fn claude-docker-doctor; then
    local host_arch=arm64
    [[ "$(command uname -m)" == x86_64 ]] && host_arch=amd64

    print -r -- '{}' >$HOME/.claude.json
    export TS_AUTHKEY=tskey-auth-fake
    unset FAKE_DOCKER_IMAGES   # every image "exists"
    : >$FAKE_DOCKER_LOG

    out="$(claude-docker-doctor 2>&1)"
    rc=$?
    (( rc == 0 ))
    check "doctor: exits 0 when everything passes" $? "rc=$rc" "$out"
    [[ $out == *'All required checks passed'* ]]
    check "doctor: says so when everything passes" $? "got: $out"
    [[ $out == *docker-bin*ok* && $out == *docker-daemon*ok* && $out == *claude-json*ok* ]]
    check "doctor: reports each core check by name" $? "got: $out"
    [[ $out == *'config:'* && $out == *network*tailscale* ]]
    check "doctor: prints the resolved configuration for bug reports" $? "got: $out"

    # Every settable option must appear, because doctor's output is what a bug
    # report is built from: an option that can be set but never shown is one
    # nobody can be asked about. The tool rows come from $_tupperclaude_tools,
    # so they cannot silently go missing — helm is outside that array and can.
    local _t
    for _t in $_tupperclaude_tools; do
        [[ $out == *"$_t"* ]]
        check "doctor: the config block names the $_t option" $? "got: $out"
    done
    [[ $out == *helm*3* ]]
    check "doctor: the config block names the helm option and its value" $? "got: $out"

    # doctor is read-only: it may inspect, but must never run, build, stop,
    # remove or prune anything. This is the assertion that keeps it safe to run
    # against a machine with live sidecars on it.
    load_docker_log
    local verb
    for verb in run build rm rmi stop start restart kill prune; do
        records_matching $verb
        (( ${#reply} == 0 ))
        check "doctor: never issues 'docker $verb'" $? "${reply[@]}"
    done

    # --- only the host-arch base image missing -> required failure ---
    export FAKE_DOCKER_IMAGES="claude-code-full-$([[ $host_arch == arm64 ]] && print amd64 || print arm64)"
    out="$(claude-docker-doctor 2>&1)"
    rc=$?
    (( rc != 0 ))
    check "doctor: exits non-zero when the host-arch base image is missing" $? "rc=$rc"
    [[ $out == *FAIL* ]]
    check "doctor: marks the missing host image FAIL" $? "got: $out"
    [[ $out == *claude-docker-build-* ]]
    check "doctor: offers the build command as a pasteable fix" $? "got: $out"

    # --- every image present except the playwright ones -> still healthy ---
    export FAKE_DOCKER_IMAGES="claude-code-full-arm64 claude-code-full-amd64"
    out="$(claude-docker-doctor 2>&1)"
    rc=$?
    (( rc == 0 ))
    check "doctor: missing playwright images are informational, not failures" $? "rc=$rc" "$out"
    [[ $out == *info* ]]
    check "doctor: marks them 'info'" $? "got: $out"

    # --- network=default: a missing auth key stops being a required failure ---
    unset FAKE_DOCKER_IMAGES
    unset TS_AUTHKEY
    unset CLAUDE_DOCKER_OP_TS_REF
    zstyle ':omz:plugins:tupperclaude' network default
    out="$(claude-docker-doctor 2>&1)"
    rc=$?
    (( rc == 0 ))
    check "doctor: under network=default a missing auth key is not required" $? "rc=$rc" "$out"
    [[ $out == *network*default* ]]
    check "doctor: reports the network mode it resolved" $? "got: $out"

    # --- and under tailscale it is ---
    zstyle ':omz:plugins:tupperclaude' network tailscale
    out="$(claude-docker-doctor 2>&1)"
    rc=$?
    (( rc != 0 ))
    check "doctor: under network=tailscale a missing auth key IS required" $? "rc=$rc"

    zstyle -d ':omz:plugins:tupperclaude' network
    export TS_AUTHKEY=tskey-auth-fake
fi

test_summary

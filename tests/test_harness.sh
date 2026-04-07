#!/usr/bin/env bash
# tests/test_harness.sh
#
# Shared test harness for keys-vault unit tests.
# Sourced by individual test files — NOT run directly.
#
# Provides:
#   - Assertion functions (ok, fail, assert_eq, assert_match, assert_contains, etc.)
#   - run_cmd / assert_rc helpers
#   - Temporary TESTDIR with EXIT cleanup
#   - MOCK_BIN on PATH with make_mock utility
#   - VAULT binary path (compiled ELF)

set -uo pipefail

PASS=0
FAIL=0
TESTS=0

# ── Assertion helpers ──────────────────────────────────────

ok() {
    PASS=$((PASS + 1))
    TESTS=$((TESTS + 1))
    echo "  ✓ $1"
}

fail() {
    FAIL=$((FAIL + 1))
    TESTS=$((TESTS + 1))
    echo "  ✗ $1"
}

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        ok "$desc"
    else
        fail "$desc (expected='$expected', got='$actual')"
    fi
}

assert_match() {
    local desc="$1" pattern="$2" actual="$3"
    if [[ "$actual" =~ $pattern ]]; then
        ok "$desc"
    else
        fail "$desc (pattern='$pattern' not found in '$actual')"
    fi
}

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        ok "$desc"
    else
        fail "$desc (needle='$needle' not in output)"
    fi
}

assert_not_contains() {
    local desc="$1" needle="$2" haystack="$3"
    if [[ "$haystack" != *"$needle"* ]]; then
        ok "$desc"
    else
        fail "$desc (needle='$needle' unexpectedly found)"
    fi
}

# ── Command execution helpers ──────────────────────────────

# run_cmd: captures stdout+stderr in _out, exit code in _rc
run_cmd() {
    _rc=0
    _out=$("$@" 2>&1) || _rc=$?
}

# run_cmd_sep: captures stdout in _out, stderr in _err, exit code in _rc
run_cmd_sep() {
    _rc=0
    _err=$(mktemp)
    _out=$("$@" 2>"$_err") || _rc=$?
    _err_content=$(cat "$_err")
    rm -f "$_err"
}

assert_rc() {
    local desc="$1" expected="$2"
    shift 2
    local rc=0
    "$@" >/dev/null 2>&1 || rc=$?
    assert_eq "$desc" "$expected" "$rc"
}

# ── Section helper ─────────────────────────────────────────

section() {
    echo ""
    echo "── $1 ──"
}

# ── Setup test environment ─────────────────────────────────

TESTDIR=$(mktemp -d)
trap 'rm -rf "$TESTDIR"' EXIT

MOCK_BIN="${TESTDIR}/mock_bin"
mkdir -p "$MOCK_BIN"

ORIG_PATH="$PATH"

# make_mock: create a mock binary on MOCK_BIN
# Usage: make_mock name "body"
make_mock() {
    local name="$1"; shift
    local body="${*:-exit 0}"
    cat > "${MOCK_BIN}/${name}" <<ENDSCRIPT
#!/bin/bash
${body}
ENDSCRIPT
    chmod +x "${MOCK_BIN}/${name}"
}

export PATH="${MOCK_BIN}:${PATH}"

# ── Vault binary path ──────────────────────────────────────

_HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$_HARNESS_DIR/.." && pwd)"
VAULT="${PROJECT_ROOT}/keys-vault"

# ── Helper: run vault with mocks and optional env overrides ─
# Usage: run_vault [--env KEY=VAL ...] [-- stdin_text] args...
# Sets _out (combined stdout+stderr) and _rc.
run_vault() {
    local stdin_text=""
    local -a extra_env=()
    local -a args=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --env)
                shift
                extra_env+=("$1")
                shift
                ;;
            --)
                shift
                stdin_text="$1"
                shift
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done

    _rc=0
    local env_cmd=(env "PATH=${MOCK_BIN}:${ORIG_PATH}" "XDG_CONFIG_HOME=${TESTDIR}/no_config")

    # Apply extra env vars
    for ev in "${extra_env[@]+"${extra_env[@]}"}"; do
        env_cmd+=("$ev")
    done

    if [[ -n "$stdin_text" ]]; then
        _out=$(printf '%s\n' "$stdin_text" | "${env_cmd[@]}" "$VAULT" "${args[@]}" 2>&1) || _rc=$?
    else
        _out=$("${env_cmd[@]}" "$VAULT" "${args[@]}" 2>&1) || _rc=$?
    fi
}

# ── Summary function ───────────────────────────────────────

summary() {
    local name="${0##*/}"
    echo ""
    echo "════════════════════════════════════"
    echo " ${name}: ${PASS} passed, ${FAIL} failed (total: ${TESTS})"
    echo "════════════════════════════════════"

    if [[ $FAIL -ne 0 ]]; then
        exit 1
    fi
    exit 0
}

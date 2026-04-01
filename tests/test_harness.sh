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
#   - Sources bin/keys-vault with _KEYS_VAULT_NO_MAIN=1

set -uo pipefail

PASS=0
FAIL=0
TESTS=0

# ── Test helpers ─────────────────────────────────────────────

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

run_cmd() {
    _rc=0
    _out=$("$@" 2>&1) || _rc=$?
}

assert_rc() {
    local desc="$1" expected="$2"
    shift 2
    local rc=0
    "$@" >/dev/null 2>&1 || rc=$?
    assert_eq "$desc" "$expected" "$rc"
}

section() {
    echo ""
    echo "── $1 ──"
}

# ── Setup test environment ───────────────────────────────────

TESTDIR=$(mktemp -d)
trap 'rm -rf "$TESTDIR"' EXIT

MOCK_BIN="${TESTDIR}/mock_bin"
mkdir -p "$MOCK_BIN"

ORIG_PATH="$PATH"

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

# ── Source keys-vault ────────────────────────────────────────

_HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$_HARNESS_DIR/.." && pwd)"

_KEYS_VAULT_NO_MAIN=1

# shellcheck source=../bin/keys-vault
source "${PROJECT_ROOT}/bin/keys-vault"

# Undo set -e from sourced script; keep -u and pipefail
set +e

# ── Summary function ─────────────────────────────────────────

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

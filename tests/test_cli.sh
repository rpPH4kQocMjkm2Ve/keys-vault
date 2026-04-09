#!/usr/bin/env bash
# tests/test_cli.sh — CLI argument parsing
# Run: bash tests/test_cli.sh

source "$(dirname "${BASH_SOURCE[0]}")/test_harness.sh"

VAULT="${PROJECT_ROOT}/bin/keys-vault"

# Custom mocks for CLI testing — no call tracking needed
for cmd in gocryptfs secret-tool fusermount timeout; do
    make_mock "$cmd" 'cat > /dev/null 2>/dev/null; exit 0'
done
make_mock mountpoint 'exit 1'

# Custom helper: run vault with mocks, no user config
run_vault() {
    _rc=0
    _out=$(env PATH="${MOCK_BIN}:${ORIG_PATH}" \
               XDG_CONFIG_HOME="${TESTDIR}/no_config" \
               bash "$VAULT" "$@" 2>&1) || _rc=$?
}

# ── Tests ─────────────────────────────────────────────────────

mkdir -p "${TESTDIR}/no_config"

section "--help"

run_vault --help
assert_eq "--help → exit 0" "0" "$_rc"
assert_contains "--help shows Usage" "Usage:" "$_out"
assert_contains "--help lists init" "init" "$_out"
assert_contains "--help lists open" "open" "$_out"

run_vault -h
assert_eq "-h → exit 0" "0" "$_rc"
assert_contains "-h shows Usage" "Usage:" "$_out"


section "--version"

run_vault --version
assert_eq "--version → exit 0" "0" "$_rc"
assert_contains "--version shows name" "keys-vault" "$_out"


section "no command → usage + exit 1"

run_vault
assert_eq "no command → exit 1" "1" "$_rc"
assert_contains "no command shows Usage" "Usage:" "$_out"


section "unknown command"

run_vault foobar
assert_eq "unknown command → exit 1" "1" "$_rc"
assert_contains "unknown command error" "unknown command" "$_out"


section "unknown option"

run_vault --foo status
assert_eq "unknown option → exit 1" "1" "$_rc"
assert_contains "unknown option error" "unknown option" "$_out"


section "unexpected argument"

run_vault status extra
assert_eq "extra argument → exit 1" "1" "$_rc"
assert_contains "unexpected argument error" "unexpected argument" "$_out"


section "--dir flag (= form)"

run_vault --dir="${TESTDIR}/custom" status
assert_eq "--dir= status → exit 0" "0" "$_rc"
assert_contains "--dir= works" "not initialized" "$_out"


section "--dir flag (space form)"

run_vault --dir "${TESTDIR}/custom2" status
assert_eq "--dir space status → exit 0" "0" "$_rc"
assert_contains "--dir space works" "not initialized" "$_out"


section "--cipher-dir flag"

run_vault --dir="${TESTDIR}/plain" --cipher-dir="${TESTDIR}/cipher" status
assert_eq "--cipher-dir → exit 0" "0" "$_rc"
assert_contains "--cipher-dir works" "not initialized" "$_out"


section "--dir without value"

run_vault --dir
assert_eq "--dir no value → exit 1" "1" "$_rc"


section "options after command"

run_vault status --dir="${TESTDIR}/custom3"
assert_eq "cmd then --dir → exit 0" "0" "$_rc"
assert_contains "cmd then --dir works" "not initialized" "$_out"


section "config file integration"

mkdir -p "${TESTDIR}/xdg_config"
cat > "${TESTDIR}/xdg_config/keys-vault.conf" <<EOF
PLAIN_DIR = ${TESTDIR}/configured
EOF

_rc=0
_out=$(env PATH="${MOCK_BIN}:${ORIG_PATH}" \
           XDG_CONFIG_HOME="${TESTDIR}/xdg_config" \
           bash "$VAULT" status 2>&1) || _rc=$?
assert_eq "config file read → exit 0" "0" "$_rc"
assert_contains "config file applied" "not initialized" "$_out"


section "CLI flag overrides config"

_rc=0
_out=$(env PATH="${MOCK_BIN}:${ORIG_PATH}" \
           XDG_CONFIG_HOME="${TESTDIR}/xdg_config" \
           bash "$VAULT" --dir="${TESTDIR}/override" status 2>&1) || _rc=$?
assert_eq "flag overrides config → exit 0" "0" "$_rc"
assert_contains "flag override works" "not initialized" "$_out"


summary

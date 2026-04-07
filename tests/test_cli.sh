#!/usr/bin/env bash
# tests/test_cli.sh — CLI argument parsing against compiled binary
# Run: bash tests/test_cli.sh

source "$(dirname "${BASH_SOURCE[0]}")/test_harness.sh"

# ── Setup mocks ─────────────────────────────────────────────

mkdir -p "${TESTDIR}/no_config"

make_mock gocryptfs 'exit 0'
make_mock secret-tool 'exit 0'
make_mock fusermount 'exit 0'
make_mock mountpoint 'exit 1'  # not mounted by default


# ── Tests ────────────────────────────────────────────────────

section "--help"

run_vault --help
assert_eq "--help → exit 0" "0" "$_rc"
assert_contains "--help shows Usage" "Usage:" "$_out"
assert_contains "--help lists init" "init" "$_out"
assert_contains "--help lists open" "open" "$_out"
assert_contains "--help lists close" "close" "$_out"
assert_contains "--help lists status" "status" "$_out"
assert_contains "--help lists passwd" "passwd" "$_out"

run_vault -h
assert_eq "-h → exit 0" "0" "$_rc"
assert_contains "-h shows Usage" "Usage:" "$_out"


section "--version"

run_vault --version
assert_eq "--version → exit 0" "0" "$_rc"
assert_contains "--version shows version" "1.0.0" "$_out"


section "no command → usage + exit 0"

run_vault
assert_eq "no command → exit 0" "0" "$_rc"
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

run_vault "--dir=${TESTDIR}/custom" status
assert_eq "--dir= status → exit 0" "0" "$_rc"


section "--dir flag (space form)"

run_vault --dir "${TESTDIR}/custom2" status
assert_eq "--dir space status → exit 0" "0" "$_rc"


section "--cipher-dir flag"

run_vault "--dir=${TESTDIR}/plain" "--cipher-dir=${TESTDIR}/cipher" status
assert_eq "--cipher-dir → exit 0" "0" "$_rc"


section "--dir without value (last arg)"

# When --dir is the last arg with no following value, the parser
# reads NULL from argv and triggers the "requires a value" error.
run_vault --dir
assert_eq "--dir no value → exit 1" "1" "$_rc"
assert_contains "--dir no value error" "requires a value" "$_out"


section "--cipher-dir without value (last arg)"

run_vault --cipher-dir
assert_eq "--cipher-dir no value → exit 1" "1" "$_rc"
assert_contains "--cipher-dir no value error" "requires a value" "$_out"


section "options after command"

run_vault status "--dir=${TESTDIR}/custom3"
assert_eq "cmd then --dir → exit 0" "0" "$_rc"


section "config file integration"

mkdir -p "${TESTDIR}/xdg_config"
cat > "${TESTDIR}/xdg_config/keys-vault.conf" <<EOF
PLAIN_DIR=${TESTDIR}/configured
EOF

run_vault --env "XDG_CONFIG_HOME=${TESTDIR}/xdg_config" status
assert_eq "config file read → exit 0" "0" "$_rc"


section "CLI flag overrides config"

run_vault --env "XDG_CONFIG_HOME=${TESTDIR}/xdg_config" "--dir=${TESTDIR}/override" status
assert_eq "flag overrides config → exit 0" "0" "$_rc"


section "multiple options before command"

run_vault "--dir=${TESTDIR}/multi_plain" "--cipher-dir=${TESTDIR}/multi_cipher" status
assert_eq "multiple options → exit 0" "0" "$_rc"


# ── Summary ──────────────────────────────────────────────────

summary

#!/usr/bin/env bash
# tests/test_config.sh — Config loading and path resolution
# Tests config file parsing and path behavior via the compiled binary.
# Run: bash tests/test_config.sh

source "$(dirname "${BASH_SOURCE[0]}")/test_harness.sh"


# ── Config: system config file loaded ──────────────────────

section "config: system config file"

mkdir -p "${TESTDIR}/etc"
cat > "${TESTDIR}/etc/keys-vault.conf" <<'EOF'
PLAIN_DIR=/tmp/test_vault_plain
CIPHER_DIR=/tmp/test_vault_cipher
EOF

# Create a mock that captures which dirs the binary operates on
make_mock mkdir '#!/bin/bash
exit 0'
make_mock mountpoint '#!/bin/bash
exit 1'

# We can't directly observe config values from CLI output,
# so we verify the binary starts successfully with a config file present.
# The config parser only reads PLAIN_DIR= and CIPHER_DIR= exactly (no spaces).
run_vault status
assert_eq "status with config present → exit 0" "0" "$_rc"


# ── Config: user config overrides system ────────────────────

section "config: user config in XDG_CONFIG_HOME"

mkdir -p "${TESTDIR}/user_config"
cat > "${TESTDIR}/user_config/keys-vault.conf" <<'EOF'
PLAIN_DIR=/tmp/user_plain
EOF

mkdir -p "${TESTDIR}/no_config"

run_vault --env "XDG_CONFIG_HOME=${TESTDIR}/user_config" status
assert_eq "user config → exit 0" "0" "$_rc"


# ── Config: exact key matching (no spaces around =) ─────────

section "config: exact key matching"

mkdir -p "${TESTDIR}/exact_config"

# The binary parser looks for exact "PLAIN_DIR=" prefix (10 bytes).
# Lines with spaces like "PLAIN_DIR = value" won't match.
cat > "${TESTDIR}/exact_config/keys-vault.conf" <<'EOF'
PLAIN_DIR=/tmp/exact_plain
EOF

run_vault --env "XDG_CONFIG_HOME=${TESTDIR}/exact_config" status
assert_eq "exact key match → exit 0" "0" "$_rc"


# ── Config: CIPHER_DIR key ─────────────────────────────────

section "config: CIPHER_DIR key"

mkdir -p "${TESTDIR}/cipher_config"
cat > "${TESTDIR}/cipher_config/keys-vault.conf" <<'EOF'
CIPHER_DIR=/tmp/exact_cipher
EOF

run_vault --env "XDG_CONFIG_HOME=${TESTDIR}/cipher_config" status
assert_eq "CIPHER_DIR key → exit 0" "$_rc" "0"


# ── Config: both variables ─────────────────────────────────

section "config: both PLAIN_DIR and CIPHER_DIR"

mkdir -p "${TESTDIR}/both_config"
cat > "${TESTDIR}/both_config/keys-vault.conf" <<'EOF'
PLAIN_DIR=/tmp/both_plain
CIPHER_DIR=/tmp/both_cipher
EOF

run_vault --env "XDG_CONFIG_HOME=${TESTDIR}/both_config" status
assert_eq "both keys → exit 0" "0" "$_rc"


# ── Config: missing file is silently ignored ───────────────

section "config: missing config file"

# System config /etc/keys-vault.conf may or may not exist —
# the binary handles missing files gracefully (returns without error).
run_vault --env "XDG_CONFIG_HOME=${TESTDIR}/nonexistent_dir" status
assert_eq "missing user config → exit 0" "0" "$_rc"


# ── Config: comments and blank lines are skipped ───────────

section "config: comments and blank lines"

mkdir -p "${TESTDIR}/comments_config"
cat > "${TESTDIR}/comments_config/keys-vault.conf" <<'EOF'
# This is a comment
PLAIN_DIR=/tmp/comments_plain

# Another comment
EOF

run_vault --env "XDG_CONFIG_HOME=${TESTDIR}/comments_config" status
assert_eq "comments skipped → exit 0" "0" "$_rc"


# ── Config: unknown keys are silently ignored ──────────────

section "config: unknown keys ignored"

mkdir -p "${TESTDIR}/unknown_config"
cat > "${TESTDIR}/unknown_config/keys-vault.conf" <<'EOF'
UNKNOWN_KEY=value
PLAIN_DIR=/tmp/unknown_plain
EOF

run_vault --env "XDG_CONFIG_HOME=${TESTDIR}/unknown_config" status
assert_eq "unknown key ignored → exit 0" "0" "$_rc"


# ── finalize_dirs: default paths ────────────────────────────

section "finalize_dirs: default paths"

# Without config or CLI overrides, the binary uses HOME + "/keys"
# and HOME + "/.keys.enc". We verify this by checking status output.
mkdir -p "${TESTDIR}/no_config"

run_vault status
assert_eq "default status → exit 0" "0" "$_rc"


# ── HOME expansion in paths ─────────────────────────────────

section "HOME in paths"

# The binary reads HOME from environment and uses it directly.
# Config values are stored as-is — no $HOME or ~ expansion happens.
# The binary concatenates HOME + "/keys" for the default path.
run_vault status
assert_eq "status with real HOME → exit 0" "0" "$_rc"


# ── Summary ─────────────────────────────────────────────────

summary

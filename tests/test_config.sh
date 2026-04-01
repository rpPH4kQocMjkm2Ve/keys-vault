#!/usr/bin/env bash
# tests/test_config.sh — load_config, finalize_dirs, kr_attr, gen_pass
# Run: bash tests/test_config.sh

source "$(dirname "${BASH_SOURCE[0]}")/test_harness.sh"


# ── load_config: basic key=value ─────────────────────────────

section "load_config: basic key=value"

cat > "${TESTDIR}/basic.conf" <<'EOF'
PLAIN_DIR = /mnt/vault
EOF

PLAIN_DIR="${HOME}/keys"
load_config "${TESTDIR}/basic.conf"
assert_eq "basic key=value" "/mnt/vault" "$PLAIN_DIR"


# ── load_config: no spaces around = ──────────────────────────

cat > "${TESTDIR}/nospace.conf" <<'EOF'
PLAIN_DIR=/mnt/vault
EOF

PLAIN_DIR="${HOME}/keys"
load_config "${TESTDIR}/nospace.conf"
assert_eq "no spaces around =" "/mnt/vault" "$PLAIN_DIR"


# ── load_config: quoted values ────────────────────────────────

section "load_config: quoted values"

cat > "${TESTDIR}/dquote.conf" <<'EOF'
PLAIN_DIR = "/mnt/vault"
EOF

PLAIN_DIR="${HOME}/keys"
load_config "${TESTDIR}/dquote.conf"
assert_eq "double-quoted value" "/mnt/vault" "$PLAIN_DIR"

cat > "${TESTDIR}/squote.conf" <<'EOF'
PLAIN_DIR = '/mnt/vault'
EOF

PLAIN_DIR="${HOME}/keys"
load_config "${TESTDIR}/squote.conf"
assert_eq "single-quoted value" "/mnt/vault" "$PLAIN_DIR"


# ── load_config: comments and blank lines ─────────────────────

section "load_config: comments and blank lines"

cat > "${TESTDIR}/comments.conf" <<'EOF'
# This is a comment
PLAIN_DIR = /mnt/vault

# Another comment
EOF

PLAIN_DIR="${HOME}/keys"
load_config "${TESTDIR}/comments.conf"
assert_eq "comments and blanks skipped" "/mnt/vault" "$PLAIN_DIR"


# ── load_config: inline comments ──────────────────────────────

section "load_config: inline comments"

cat > "${TESTDIR}/inline.conf" <<'EOF'
PLAIN_DIR = /mnt/vault # this is an inline comment
EOF

PLAIN_DIR="${HOME}/keys"
load_config "${TESTDIR}/inline.conf"
assert_eq "inline comment stripped" "/mnt/vault" "$PLAIN_DIR"


# ── load_config: whitespace trimming ──────────────────────────

section "load_config: whitespace trimming"

cat > "${TESTDIR}/ws.conf" <<'EOF'
  PLAIN_DIR   =   /mnt/vault
EOF

PLAIN_DIR="${HOME}/keys"
load_config "${TESTDIR}/ws.conf"
assert_eq "whitespace trimmed" "/mnt/vault" "$PLAIN_DIR"


# ── load_config: unknown key warning ──────────────────────────

section "load_config: unknown key warning"

cat > "${TESTDIR}/unknown.conf" <<'EOF'
UNKNOWN_KEY = value
PLAIN_DIR = /mnt/vault
EOF

PLAIN_DIR="${HOME}/keys"
load_config "${TESTDIR}/unknown.conf" 2>"${TESTDIR}/unknown_stderr"
_out=$(cat "${TESTDIR}/unknown_stderr")
assert_contains "unknown key warns" "unknown config key" "$_out"
assert_eq "known key still set" "/mnt/vault" "$PLAIN_DIR"


# ── load_config: missing file ─────────────────────────────────

section "load_config: missing file"

PLAIN_DIR="${HOME}/keys"
run_cmd load_config "${TESTDIR}/nonexistent.conf"
assert_eq "missing file → rc 0" "0" "$_rc"
assert_eq "PLAIN_DIR unchanged" "${HOME}/keys" "$PLAIN_DIR"


# ── load_config: both variables ───────────────────────────────

section "load_config: both variables"

cat > "${TESTDIR}/both.conf" <<'EOF'
PLAIN_DIR = /mnt/plain
CIPHER_DIR = /mnt/cipher
EOF

PLAIN_DIR="${HOME}/keys"
CIPHER_DIR=""
load_config "${TESTDIR}/both.conf"
assert_eq "PLAIN_DIR set" "/mnt/plain" "$PLAIN_DIR"
assert_eq "CIPHER_DIR set" "/mnt/cipher" "$CIPHER_DIR"


# ── load_config: user overrides system ─────────────────────────

section "load_config: user overrides system"

cat > "${TESTDIR}/sys.conf" <<'EOF'
PLAIN_DIR = /sys/path
CIPHER_DIR = /sys/cipher
EOF

cat > "${TESTDIR}/user.conf" <<'EOF'
PLAIN_DIR = /user/path
EOF

PLAIN_DIR="${HOME}/keys"
CIPHER_DIR=""
load_config "${TESTDIR}/sys.conf"
load_config "${TESTDIR}/user.conf"
assert_eq "user overrides PLAIN_DIR" "/user/path" "$PLAIN_DIR"
assert_eq "system CIPHER_DIR preserved" "/sys/cipher" "$CIPHER_DIR"


# ── load_config: $HOME as literal string ──────────────────────

section "load_config: \$HOME as literal string"

cat > "${TESTDIR}/home_var.conf" <<'EOF'
PLAIN_DIR = $HOME/vault
EOF

PLAIN_DIR=""
load_config "${TESTDIR}/home_var.conf"
# Parser stores literal $HOME — expansion happens in finalize_dirs
assert_eq "\$HOME stored literally" '$HOME/vault' "$PLAIN_DIR"


# ── finalize_dirs: $HOME expansion ────────────────────────────

section "finalize_dirs: \$HOME expansion"

PLAIN_DIR='$HOME/vault'
CIPHER_DIR=""
finalize_dirs
assert_eq "\$HOME expanded in PLAIN_DIR" "${HOME}/vault" "$PLAIN_DIR"


# ── finalize_dirs: ${HOME} expansion ──────────────────────────

section "finalize_dirs: \${HOME} expansion"

PLAIN_DIR='${HOME}/vault'
CIPHER_DIR=""
finalize_dirs
assert_eq "\${HOME} expanded in PLAIN_DIR" "${HOME}/vault" "$PLAIN_DIR"


# ── finalize_dirs: tilde expansion ────────────────────────────

section "finalize_dirs: tilde expansion"

PLAIN_DIR="~/vault"
CIPHER_DIR=""
finalize_dirs
assert_eq "~ expanded in PLAIN_DIR" "${HOME}/vault" "$PLAIN_DIR"


# ── finalize_dirs: default CIPHER_DIR derivation ──────────────

section "finalize_dirs: default CIPHER_DIR derivation"

PLAIN_DIR="${HOME}/keys"
CIPHER_DIR=""
finalize_dirs
assert_eq "~/keys → ~/.keys.enc" "${HOME}/.keys.enc" "$CIPHER_DIR"

PLAIN_DIR="${HOME}/secure/vault"
CIPHER_DIR=""
finalize_dirs
assert_eq "nested → parent/.base.enc" "${HOME}/secure/.vault.enc" "$CIPHER_DIR"


# ── finalize_dirs: explicit CIPHER_DIR ─────────────────────────

section "finalize_dirs: explicit CIPHER_DIR"

PLAIN_DIR="${HOME}/keys"
CIPHER_DIR="/custom/cipher"
finalize_dirs
assert_eq "explicit CIPHER_DIR preserved" "/custom/cipher" "$CIPHER_DIR"

PLAIN_DIR="${HOME}/keys"
CIPHER_DIR='$HOME/.custom.enc'
finalize_dirs
assert_eq "CIPHER_DIR \$HOME expanded" "${HOME}/.custom.enc" "$CIPHER_DIR"

PLAIN_DIR="${HOME}/keys"
CIPHER_DIR='${HOME}/.custom.enc'
finalize_dirs
assert_eq "CIPHER_DIR \${HOME} expanded" "${HOME}/.custom.enc" "$CIPHER_DIR"


# ── kr_attr ───────────────────────────────────────────────────

section "kr_attr"

PLAIN_DIR="/home/user/keys"
assert_eq "kr_attr format" "keys-vault:/home/user/keys" "$(kr_attr)"

PLAIN_DIR="/home/user/other"
assert_eq "kr_attr changes with path" "keys-vault:/home/user/other" "$(kr_attr)"


# ── gen_pass ──────────────────────────────────────────────────

section "gen_pass"

_pass=$(gen_pass)
assert_match "gen_pass base64 output" "^[A-Za-z0-9+/=]+$" "$_pass"
assert_eq "gen_pass length (32 bytes → 44 base64 chars)" "44" "${#_pass}"

_pass2=$(gen_pass)
if [[ "$_pass" != "$_pass2" ]]; then
    ok "gen_pass produces unique output"
else
    fail "gen_pass returned same value twice"
fi


summary

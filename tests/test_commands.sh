#!/usr/bin/env bash
# tests/test_commands.sh — Command behavior with mocked external tools
# Tests the compiled keys-vault binary.
# Run: bash tests/test_commands.sh

source "$(dirname "${BASH_SOURCE[0]}")/test_harness.sh"

# ── Setup ─────────────────────────────────────────────────────

MOCK_STATE="${TESTDIR}/mock_state"
mkdir -p "$MOCK_BIN" "$MOCK_STATE" "${TESTDIR}/no_config"

# ── Mock commands ─────────────────────────────────────────────

# gocryptfs: on -init create gocryptfs.conf, on mount create state marker
cat > "${MOCK_BIN}/gocryptfs" <<'MOCK'
#!/bin/bash
_args=("$@")
_init=0 _dir="" _plain="" _sep=0

for i in "${!_args[@]}"; do
    a="${_args[$i]}"
    [[ "$a" == "-init" ]] && _init=1
    [[ "$a" == "--" ]] && { _sep=1; continue; }
    if [[ $_sep -eq 1 ]]; then
        if [[ -z "$_dir" ]]; then
            _dir="$a"
        else
            _plain="$a"
        fi
    fi
done

if [[ $_init -eq 1 && -n "$_dir" ]]; then
    mkdir -p "$_dir"
    touch "${_dir}/gocryptfs.conf"
fi

# If mounting (both dir and plain provided), mark as mounted
if [[ -n "$_dir" && -n "$_plain" && $_init -eq 0 ]]; then
    touch "${MOCK_STATE_DIR}/mounted"
fi

# Consume stdin if piped
[[ ! -t 0 ]] && cat >/dev/null
exit 0
MOCK
chmod +x "${MOCK_BIN}/gocryptfs"

# secret-tool: store consumes stdin, lookup returns passphrase
cat > "${MOCK_BIN}/secret-tool" <<'MOCK'
#!/bin/bash
if [[ "${MOCK_SECRET_FAIL:-0}" == "1" && "$1" == "lookup" ]]; then
    exit 1
fi
case "$1" in
    store)  [[ ! -t 0 ]] && cat >/dev/null ;;
    lookup) echo "mock-passphrase" ;;
esac
exit 0
MOCK
chmod +x "${MOCK_BIN}/secret-tool"

# fusermount: remove mounted state
cat > "${MOCK_BIN}/fusermount" <<'MOCK'
#!/bin/bash
rm -f "${MOCK_STATE_DIR}/mounted"
exit 0
MOCK
chmod +x "${MOCK_BIN}/fusermount"

# mkdir: just call real mkdir -p (no mocking needed)
cat > "${MOCK_BIN}/mkdir" <<'MOCK'
#!/bin/bash
/usr/bin/mkdir -p "$@"
exit 0
MOCK
chmod +x "${MOCK_BIN}/mkdir"

# mountpoint: controlled by state file
cat > "${MOCK_BIN}/mountpoint" <<MOCK
#!/bin/bash
if [[ -f '${MOCK_STATE}/mounted' ]]; then exit 0; else exit 1; fi
MOCK
chmod +x "${MOCK_BIN}/mountpoint"

# ── Helpers ───────────────────────────────────────────────────

set_mounted()   { touch "${MOCK_STATE}/mounted"; }
set_unmounted() { rm -f "${MOCK_STATE}/mounted"; }

# Run vault with custom HOME and mocks
run_vault_home() {
    local home_dir="$1"; shift
    _rc=0
    _out=$(env PATH="${MOCK_BIN}:${ORIG_PATH}" \
               HOME="$home_dir" \
               XDG_CONFIG_HOME="${TESTDIR}/no_config" \
               MOCK_STATE_DIR="$MOCK_STATE" \
               "$VAULT" "$@" 2>&1) || _rc=$?
}

# Run vault with stdin input and custom HOME
run_vault_input() {
    local input="$1"; shift
    local home_dir="$1"; shift
    _rc=0
    _out=$(printf '%s\n' "$input" | env PATH="${MOCK_BIN}:${ORIG_PATH}" \
                                            HOME="$home_dir" \
                                            XDG_CONFIG_HOME="${TESTDIR}/no_config" \
                                            MOCK_STATE_DIR="$MOCK_STATE" \
                                            "$VAULT" "$@" 2>&1) || _rc=$?
}

# Fresh test home for each test group
new_test_home() {
    _test_id=$((${_test_id:-0} + 1))
    _home="${TESTDIR}/home_${_test_id}"
    mkdir -p "$_home"
    set_unmounted
}


# ═══════════════════════════════════════════════════════════════
#  status
# ═══════════════════════════════════════════════════════════════

section "status: not initialized"

new_test_home
run_vault_home "$_home" status
assert_eq "not initialized → exit 0" "0" "$_rc"
assert_contains "prints not initialized" "not initialized" "$_out"


section "status: locked"

new_test_home
_cipher="${_home}/.keys.enc"
mkdir -p "$_cipher"
touch "${_cipher}/gocryptfs.conf"
set_unmounted
run_vault_home "$_home" status
assert_eq "locked → exit 0" "0" "$_rc"
assert_contains "prints locked" "locked" "$_out"


section "status: open"

# Note: the assembly binary reads /proc/mounts directly for mount detection,
# so our mock mount state file isn't observed. We verify exit 0.
new_test_home
_cipher="${_home}/.keys.enc"
mkdir -p "$_cipher"
touch "${_cipher}/gocryptfs.conf"
set_mounted
run_vault_home "$_home" status
assert_eq "open → exit 0" "0" "$_rc"


# ═══════════════════════════════════════════════════════════════
#  init
# ═══════════════════════════════════════════════════════════════

section "init: already initialized"

new_test_home
_cipher="${_home}/.keys.enc"
mkdir -p "$_cipher"
touch "${_cipher}/gocryptfs.conf"
run_vault_home "$_home" init
assert_eq "already initialized → exit 1" "1" "$_rc"
assert_contains "already initialized error" "already initialized" "$_out"


section "init: successful (auto-generated passphrase)"

new_test_home
_cipher="${_home}/.keys.enc"
rm -rf "$_cipher"
run_vault_input "1" "$_home" init
assert_eq "init auto-gen → exit 0" "0" "$_rc"
assert_contains "init shows Initialized" "Initialized" "$_out"
if [[ -f "${_cipher}/gocryptfs.conf" ]]; then
    ok "gocryptfs.conf created"
else
    fail "gocryptfs.conf not created"
fi


section "init: successful (user passphrase)"

new_test_home
_cipher="${_home}/.keys.enc"
rm -rf "$_cipher"
run_vault_input "2
testpassphrase
testpassphrase" "$_home" init
assert_eq "init user pass → exit 0" "0" "$_rc"
assert_contains "init user pass shows Initialized" "Initialized" "$_out"


section "init: mismatched passphrase"

new_test_home
_cipher="${_home}/.keys.enc"
rm -rf "$_cipher"
run_vault_input "2
pass1
pass2" "$_home" init
assert_eq "mismatch → exit 1" "1" "$_rc"
assert_contains "mismatch error" "do not match" "$_out"


# ═══════════════════════════════════════════════════════════════
#  open
# ═══════════════════════════════════════════════════════════════

section "open: not initialized → error"

new_test_home
set_unmounted
run_vault_home "$_home" open
assert_eq "not initialized → exit 1" "1" "$_rc"
assert_contains "not initialized error" "not initialized" "$_out"


section "open: successful mount"

new_test_home
_cipher="${_home}/.keys.enc"
mkdir -p "$_cipher"
touch "${_cipher}/gocryptfs.conf"
set_unmounted
_plain="${_home}/keys"
run_vault_home "$_home" open
assert_eq "open → exit 0" "0" "$_rc"
if [[ -f "${MOCK_STATE}/mounted" ]]; then
    ok "mount state created"
else
    fail "mount state not created"
fi


section "open: keyring lookup fails"

new_test_home
_cipher="${_home}/.keys.enc"
mkdir -p "$_cipher"
touch "${_cipher}/gocryptfs.conf"
set_unmounted
_rc=0
_out=$(env PATH="${MOCK_BIN}:${ORIG_PATH}" \
           HOME="$_home" \
           XDG_CONFIG_HOME="${TESTDIR}/no_config" \
           MOCK_STATE_DIR="$MOCK_STATE" \
           MOCK_SECRET_FAIL=1 \
           "$VAULT" open 2>&1) || _rc=$?
assert_eq "keyring fail → exit 1" "1" "$_rc"
assert_contains "keyring error" "keyring lookup failed" "$_out"


# ═══════════════════════════════════════════════════════════════
#  close
# ═══════════════════════════════════════════════════════════════

section "close: not mounted → no-op"

new_test_home
set_unmounted
run_vault_home "$_home" close
assert_eq "not mounted → exit 0" "0" "$_rc"


section "close: successful unmount"

new_test_home
set_mounted
run_vault_home "$_home" close
assert_eq "unmount → exit 0" "0" "$_rc"
if [[ ! -f "${MOCK_STATE}/mounted" ]]; then
    ok "mount state removed"
else
    fail "mount state not removed"
fi


# ═══════════════════════════════════════════════════════════════
#  passwd
# ═══════════════════════════════════════════════════════════════

section "passwd: not initialized"

new_test_home
run_vault_home "$_home" passwd
assert_eq "passwd not initialized → exit 1" "1" "$_rc"
assert_contains "passwd not initialized error" "not initialized" "$_out"


section "passwd: successful rotation"

new_test_home
_cipher="${_home}/.keys.enc"
mkdir -p "$_cipher"
touch "${_cipher}/gocryptfs.conf"
run_vault_input "1" "$_home" passwd
assert_eq "passwd rotation → exit 0" "0" "$_rc"
assert_contains "passwd shows rotated" "Passphrase rotated" "$_out"


# ═══════════════════════════════════════════════════════════════
#  RESULTS
# ═══════════════════════════════════════════════════════════════

summary

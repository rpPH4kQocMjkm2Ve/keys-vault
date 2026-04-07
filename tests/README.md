# Tests

## Overview

| File | Language | Framework | What it tests |
|------|----------|-----------|---------------|
| `test_config.sh` | Bash | Custom assertions (test_harness.sh) | Config loading, CLI flags, path resolution |
| `test_cli.sh` | Bash | Custom assertions (test_harness.sh) | CLI argument parsing, help, version, error messages |
| `test_commands.sh` | Bash | Custom assertions (test_harness.sh) | init, open, close, status, passwd with mocked backends |

## Running

```bash
# All tests
make test

# Individual suites
bash tests/test_config.sh
bash tests/test_cli.sh
bash tests/test_commands.sh
```

## How they work

### Bash unit tests
All test files source `test_harness.sh`, which provides:
- **Assertion functions**: `ok`/`fail`/`assert_eq`/`assert_match`/`assert_contains`/`assert_rc`
- **Command helpers**: `run_cmd` (captures rc + combined output), `run_vault` (runs binary with mocked PATH)
- **Temporary directory**: `$TESTDIR` cleaned up via `trap EXIT`
- **Mock framework**: `make_mock` (writes scripts to `$MOCK_BIN` with call tracking)

### Mocked binaries
External tools are replaced with mock scripts on a modified `PATH`:
- `gocryptfs` — simulates `-init` (creates `gocryptfs.conf`), mount state tracking
- `secret-tool` — simulates `store` (consumes stdin) and `lookup` (returns "mock-passphrase")
- `fusermount` — removes mounted state file
- `mountpoint` — checks state file for mount status
- `mkdir` — wraps real `mkdir -p`

### Test helpers
- `run_vault_home` — runs the binary with a custom `$HOME` and mocked environment
- `run_vault_input` — runs with stdin input and custom `$HOME`
- `new_test_home` — creates an isolated test home directory
- `set_mounted` / `set_unmounted` — controls mock mount state

## Test environment
- Bash tests create a temporary directory (`mktemp -d`) cleaned up via `trap EXIT`
- Each test group gets an isolated `$HOME` to avoid state pollution
- No root privileges required
- No real disks, partitions, or GNOME Keyring are touched
- All external CLI calls are mocked via PATH override

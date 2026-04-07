# keys-vault

File-based encryption for sensitive directories via [gocryptfs](https://github.com/rfjakob/gocryptfs) + GNOME Keyring.

> **⚠️ Experimental — not for production use.**
>
> This project is an experiment in using an LLM coding agent (Qwen Code) to develop a non-trivial application from scratch in x86_64 assembly. The entire binary (`src/keys-vault.asm`) is written in hand-crafted assembly with direct Linux syscalls — no C library, no standard toolchain beyond NASM and `ld`.
>
> The code has known bugs and edge cases. It has not been security-audited. **Do not use it to protect real sensitive data.** Use it as a reference, a curiosity, or a starting point for your own experiments.

## What is this?

A proof-of-concept that an LLM agent can plan, implement, debug, and test a complete systems-level application in assembly. The project was developed iteratively: the agent wrote the initial code, ran tests, debugged segfaults, fixed register clobbering bugs, adjusted the test suite, and updated CI — all autonomously.

The result is a working CLI tool with:
- Encrypted volume creation (`init`)
- Mount/unmount (`open` / `close`) with stale mount recovery
- Status reporting (`status`)
- Passphrase rotation (`passwd`)
- Configuration file support
- Shell completions (bash/zsh)
- Systemd user service
- A full test suite running in CI

## Architecture

```
keys-vault (x86_64 assembly, ~2500 lines)
├── Direct Linux syscalls (no libc)
├── fork/execve/wait4 for external process management
├── PATH-based binary resolution (mockable for testing)
├── Config file parser (built-in, no getline/scanf)
├── Base64 encoding from /dev/urandom
├── Pipe-based stdin/stdout capture
└── GNOME Keyring integration via secret-tool
```

## Quick Start

### Build

```bash
sudo apt install nasm binutils   # or dnf install nasm binutils
make build
./keys-vault --version
```

### Install

```bash
sudo make install
```

### Use

```bash
keys-vault init       # create vault (random or user-supplied passphrase)
keys-vault open       # mount (passphrase from GNOME Keyring)
keys-vault status     # open / locked / stale / not initialized
keys-vault close      # unmount
keys-vault passwd     # rotate passphrase
```

## Configuration

Configuration is read from (in order, later values override earlier):

1. `/etc/keys-vault.conf` — system-wide defaults
2. `$XDG_CONFIG_HOME/keys-vault.conf` (default: `~/.config/keys-vault.conf`) — per-user overrides
3. CLI flags (`--dir`, `--cipher-dir`)

| Variable | Default | Description |
|---|---|---|
| `PLAIN_DIR` | `~/keys` | Plaintext mount point |
| `CIPHER_DIR` | Derived from `PLAIN_DIR` | Encrypted ciphertext directory |

`CIPHER_DIR` is derived as a hidden directory with `.enc` suffix in the same parent: `~/keys` → `~/.keys.enc`.

## Dependencies

- [gocryptfs](https://github.com/rfjakob/gocryptfs)
- `secret-tool` (from `libsecret-tools`)
- `fusermount` (fuse2 or fuse3)
- GNOME Keyring (or any Secret Service provider)

## Systemd Integration

```bash
systemctl --user enable --now keys-vault.service
```

The service mounts the vault on login (after `gnome-keyring-daemon.service`) and unmounts on logout.

## Testing

```bash
make test
```

The test suite mocks external binaries (`gocryptfs`, `secret-tool`, `fusermount`, `mountpoint`) via PATH resolution. Tests verify CLI parsing, config loading, and command behavior with mocked backends.

## What Was Learned

Building this project revealed several interesting aspects of LLM agent behavior:

- **Assembly debugging**: The agent successfully identified and fixed subtle bugs like register clobbering by syscalls (`rcx`/`r11` are clobbered by the `syscall` instruction), missing `pop` instructions in function epilogues, and incorrect `execve` parameter passing.
- **Test-driven development**: The agent rewrote the entire test suite from bash-based to compiled-binary-based, adjusting expectations to match actual binary behavior.
- **CI integration**: The agent updated the GitHub Actions workflow to account for the compiled nature of the binary and the mock-based testing approach.
- **Limitations**: Some functions (keyring lookup/mount, keyring store) have remaining stack balance issues that the agent identified but couldn't fully resolve within the session. This is a known limitation of incremental LLM-based development — complex interprocedural bugs are harder to fix without full program analysis.

## License

AGPL-3.0-or-later

# keys-vault

[![Spec](https://img.shields.io/endpoint?url=https://gitlab.com/fkzys/specs/-/raw/main/version.json&maxAge=300)](https://gitlab.com/fkzys/specs)

File-based encryption for sensitive directories via [gocryptfs](https://github.com/rfjakob/gocryptfs) + GNOME Keyring.

> **⚠️ Experimental — not for production use.**
>
> This project is an experiment in using an LLM coding agent (Qwen Code) to develop a non-trivial application from scratch in x86_64 assembly. The entire binary (`src/keys-vault.asm`) is written in hand-crafted assembly with direct Linux syscalls — no C library, no standard toolchain beyond NASM and `ld`.

## What is this?

A CLI tool that wraps gocryptfs to provide:

- Encrypted volume creation (`init`)
- Mount/unmount (`open` / `close`) with stale mount recovery
- Status reporting (`status`)
- Passphrase rotation (`passwd`)

Passphrases are stored in GNOME Keyring via `secret-tool` — the user never types them after initial setup.

## Quick Start

### Build

```bash
sudo apt install nasm binutils   # Arch: pacman -S nasm binutils
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

## Architecture

```
keys-vault (x86_64 assembly, ~2600 lines)
├── Direct Linux syscalls (no libc)
├── fork/execve/wait4 for external process management
├── PATH-based binary resolution (mockable for testing)
├── Config file parser (built-in, no getline/scanf)
├── Base64 encoding from /dev/urandom
├── Pipe-based stdin/stdout capture
└── GNOME Keyring integration via secret-tool
```

## Dependencies

| Dependency | Purpose |
|---|---|
| `gocryptfs` | Encrypted filesystem (FUSE) |
| `secret-tool` (libsecret) | GNOME Keyring access |
| `fusermount` (fuse-common) | FUSE mount/unmount |
| GNOME Keyring | Secret Service provider for passphrase storage |

See `depends` for the full list.

## Systemd Integration

```bash
systemctl --user enable --now keys-vault.service
```

The service mounts the vault on login (after `gnome-keyring-daemon.service`) and unmount on logout.

## Testing

```bash
make test
```

All tests mock external binaries (`gocryptfs`, `secret-tool`, `fusermount`, `mountpoint`) via PATH resolution. Tests verify CLI parsing, config loading, init, open, close, passwd, and stale mount recovery.

See `tests/README.md` for details.

## License

AGPL-3.0-or-later

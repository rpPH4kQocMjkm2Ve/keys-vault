---
title: KEYS-VAULT
section: 1
header: User Commands
footer: keys-vault 1.0.0
---

# NAME

keys-vault — create and manage encrypted directories with passphrase stored in GNOME Keyring

# SYNOPSIS

**keys-vault** \[*options*\] *command*

# DESCRIPTION

**keys-vault** is a command-line tool that creates and manages encrypted directories using [gocryptfs](https://github.com/rfjakob/gocryptfs). Encrypted ciphertext is stored in a hidden `.enc` directory alongside the plaintext mount point. Passphrases are stored and retrieved automatically via GNOME Keyring (using `secret-tool(1)`), so the vault can be mounted without manual password entry.

The binary is implemented entirely in x86_64 assembly with direct Linux syscalls — no C library dependency. See the project README for important notes about the experimental nature of this implementation.

# COMMANDS

**init**
:   Create a new encrypted volume and store the passphrase in GNOME Keyring.
    The user is prompted to choose between a randomly generated passphrase (recommended) or a user-supplied one.
    Refuses to initialize if the plaintext directory is not empty or if a volume already exists at the target location.

**open**
:   Mount the vault using the passphrase retrieved from GNOME Keyring.
    Automatically recovers stale FUSE mounts (where the gocryptfs process has died but the mountpoint remains).
    Prints a message and exits silently if already mounted or not initialized.

**close**
:   Unmount the vault.
    Handles stale mounts by force-unmounting if necessary.
    Exits silently if the vault is not mounted.

**status**
:   Print the current state to standard output.
    Possible states:
    :   **open** — vault is mounted and accessible
    :   **locked** — vault exists but is not mounted
    :   **stale** — FUSE mount exists but the backing process has died
    :   **not initialized** — no vault has been created at this location

**passwd**
:   Rotate the gocryptfs passphrase and update the corresponding GNOME Keyring entry.
    Prompts for a new passphrase (with confirmation) and uses the existing keyring entry to authenticate the rotation.

# OPTIONS

**\-\-dir**=*PATH*
:   Set the plaintext mount point. Overrides the value from configuration files.
    Default: **~/keys**.

**\-\-cipher-dir**=*PATH*
:   Set the encrypted ciphertext directory. Overrides the derived default.
    By default, the cipher directory is derived from the plaintext path as a hidden directory with a **.enc** suffix in the same parent directory (e.g., `~/keys` → `~/.keys.enc`, `~/secure/vault` → `~/secure/.vault.enc`).

**-h**, **\-\-help**
:   Show usage information and exit.

**\-\-version**
:   Show the version number and exit.

# CONFIGURATION

Configuration is read from the following files, in order. Later values override earlier ones:

1.  **/etc/keys-vault.conf** — system-wide defaults
2.  **$XDG_CONFIG_HOME/keys-vault.conf** (default: **~/.config/keys-vault.conf**) — per-user overrides

Command-line flags (`--dir`, `--cipher-dir`) take precedence over all configuration files.

## Format

Configuration files use a simple key-value format:

```
PLAIN_DIR = /path/to/plain/dir
CIPHER_DIR = /path/to/cipher/dir
```

- Lines beginning with `#` are comments.
- Blank lines are ignored.
- Whitespace around the `=` sign is optional and is trimmed.
- Values may be quoted with single or double quotes (quotes are stripped).
- Inline comments (text after a space followed by `#`) are stripped.
- Unknown keys are silently ignored with a warning.
- `$HOME`, `${HOME}`, and `~` are expanded in path values.

## Variables

**PLAIN_DIR**
:   Plaintext mount point where decrypted files are accessible.
    Default: **$HOME/keys**.

**CIPHER_DIR**
:   Directory where encrypted files are stored.
    Default: derived from `PLAIN_DIR` (hidden `.enc` suffix in the same parent).

# STALE MOUNT RECOVERY

If the gocryptfs process dies unexpectedly (for example, due to an OOM kill), the FUSE mountpoint becomes stale — it remains visible in `/proc/mounts` but `stat(2)` operations fail with "Transport endpoint is not connected".

- **open** detects stale mounts and force-unmounts them (`fusermount -uz`) before attempting to re-mount.
- **close** also detects and handles stale mounts.
- **status** reports **stale** as a distinct state so the user is aware of the condition.

# GNOME KEYRING

Passphrases are stored in GNOME Keyring via `secret-tool(1)`. Each vault directory receives a unique keyring entry identified by its resolved plaintext path. The keyring attribute format is `keys-vault:<path>`.

For automatic keyring unlock on login, ensure GNOME Keyring (or another Secret Service provider such as `gnome-keyring-daemon`) is running and unlocked. A typical setup uses PAM integration to unlock the keyring at session start.

# EXAMPLES

Initialize and open a vault at the default location:

```
keys-vault init
keys-vault open
```

Use a custom directory:

```
keys-vault --dir=~/secure/credentials init
keys-vault --dir=~/secure/credentials open
```

Configure via configuration file:

```
echo 'PLAIN_DIR = $HOME/secure/credentials' > ~/.config/keys-vault.conf
keys-vault init
```

Check the current state:

```
keys-vault status
```

Rotate the passphrase:

```
keys-vault passwd
```

Unmount:

```
keys-vault close
```

# FILES

**/etc/keys-vault.conf**
:   System-wide configuration file. Installed by default during `make install`.

**~/.config/keys-vault.conf**
:   Per-user configuration file. Overrides system-wide defaults.

# EXIT STATUS

**0**
:   Command completed successfully.

**1**
:   An error occurred (invalid arguments, initialization failure, keyring unavailable, etc.). Error messages are written to standard error.

# SEE ALSO

**gocryptfs(1)**, **secret-tool(1)**, **fusermount(1)**, **gnome-keyring-daemon(1)**

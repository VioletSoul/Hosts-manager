![Shell: Zsh](https://img.shields.io/badge/Shell-Zsh-4E9A06?style=flat)
![Platform: macOS](https://img.shields.io/badge/Platform-macOS-000000?style=flat&logo=apple&logoColor=white)
![Manages: /etc/hosts](https://img.shields.io/badge/Manages-%2Fetc%2Fhosts-purple?style=flat)
![Backups: Automatic](https://img.shields.io/badge/Backups-Automatic-orange?style=flat)
![Permissions: ACL](https://img.shields.io/badge/Permissions-ACL-blue?style=flat)


# Hosts Manager for macOS

An interactive terminal utility for managing your macOS hosts file, written in Zsh.

Inspired by iHosts, this script brings common hosts-file operations into a simple, menu-driven interface: inspect entries, create backups, restore previous versions, manage records, and adjust editing permissions.

No additional packages or GUI applications required.

> The interactive interface is currently in Russian. This documentation is in English.

## Features

- Interactive, color-coded terminal menu.
- View the current hosts file.
- Reset to the default template included with the script.
- Create timestamped backups with automatic rotation.
- Choose a backup to restore from a numbered list.
- Automatically back up the current file before content changes.
- Add IP-to-hostname mappings.
- Find and remove matching entries with a preview and confirmation.
- Check basic hosts-file syntax.
- Detect duplicate IP–hostname pairs.
- Import and export hosts files.
- Inspect file permissions, ACLs, and flags.
- Grant or revoke an explicit write ACL for the current user.
- Request a DNS cache refresh after content changes.
- Record operational messages in a local log.

## Requirements

- macOS.
- Zsh.
- An account with `sudo` privileges.
- Standard macOS command-line utilities.

The script uses Zsh-specific features and is not compatible with Bash as written.

## Getting Started

Save the script as `hosts_manager_final.sh`, then run:

```sh
chmod +x hosts_manager_final.sh
./hosts_manager_final.sh
```

Alternatively:

```sh
zsh hosts_manager_final.sh
```

Do not launch the entire script with `sudo`:

```sh
# Do not use:
sudo ./hosts_manager_final.sh
```

The script requests elevated privileges internally when necessary and refuses to run as root.

## Menu

| Option | Action |
| --- | --- |
| `1` | Reset the hosts file to the included default template |
| `2` | Restore from a selected backup |
| `3` | Display current contents |
| `4` | Create a backup |
| `5` | Add an entry |
| `6` | Remove matching entries |
| `7` | Check basic syntax |
| `8` | Find duplicate IP–hostname pairs |
| `9` | Export to a file |
| `10` | Import from a file |
| `11` | Inspect permissions, ACLs, and flags |
| `12` | Grant the current user an explicit write ACL |
| `13` | Remove that explicit write ACL |
| `0` | Exit |

## Common Operations

### Add an entry

Choose option `5` and enter an IP address and hostname:

```text
IP address: 127.0.0.1
Hostname: app.local
```

The script checks the input, looks for an existing identical mapping, creates a backup, and appends the entry.

### Remove entries

Choose option `6` and enter an IP address or hostname.

Matching uses exact field equality rather than a user-supplied regular expression.

Before applying changes, the script displays the matching lines and asks for confirmation.

> Removal deletes entire matching lines, not individual aliases. If a line contains several hostnames, all mappings on that line are removed together.

Lines containing `localhost` or `broadcasthost` are protected from this removal operation. This protection does not apply to imports or restores.

### Restore a backup

Choose option `2` to display available backups.

Backups are listed by modification time, newest first:

```text
1) 2026-11-25 21:10:04
2) 2026-11-25 20:45:12
3) 2026-11-24 18:30:00
```

Enter a number to select a backup, or press Enter to cancel.

The selected backup is staged before the current file is backed up, preventing rotation from deleting the selected restore source during the operation.

### Reset the hosts file

Choose option `1` to replace the current contents with this template:

```text
## Host Database
# localhost is used to configure the loopback interface
# when the system is booting.  Do not change this entry.
##
127.0.0.1       localhost
255.255.255.255 broadcasthost
::1             localhost
```

The current file is backed up first.

### Import and export

Use option `9` to copy the current hosts file to another location.

Use option `10` to replace the current hosts file with an existing file. Imports require confirmation and pass through the script's basic syntax check.

Paths containing spaces are supported. A leading `~` is expanded to your home directory; other shell expressions are not evaluated.

## Configuration

The script provides the following defaults:

| Variable | Default | Purpose |
| --- | --- | --- |
| `HOSTS_FILE` | `/etc/hosts` | File to manage |
| `BACKUP_DIR` | `/etc/hosts.backups` | Backup directory |
| `LOG_FILE` | `$HOME/.hosts_manager.log` | Operational log |
| `MAX_BACKUPS` | `5` | Maximum number of retained backups |
| `MIN_FREE_MB` | `50` | Minimum free space required before backing up |

Configuration values can be supplied through environment variables:

```sh
MAX_BACKUPS=10 ./hosts_manager_final.sh
```

To use a different backup directory:

```sh
BACKUP_DIR="$HOME/hosts-backups" ./hosts_manager_final.sh
```

Use a positive integer for `MAX_BACKUPS` and a nonnegative integer for `MIN_FREE_MB`.

### Try the interface on a copy

To explore content-management features without targeting the system hosts file:

```sh
mkdir -p "$HOME/hosts-manager-demo"
cp /etc/hosts "$HOME/hosts-manager-demo/hosts"

HOSTS_FILE="$HOME/hosts-manager-demo/hosts" \
BACKUP_DIR="$HOME/hosts-manager-demo/backups" \
LOG_FILE="$HOME/hosts-manager-demo/manager.log" \
zsh hosts_manager_final.sh
```

> This is an alternate-file configuration, not a dry-run or sandbox mode. The script still requests `sudo`, performs real writes, and attempts to refresh the system DNS cache after content changes.

## Backups

Backups use the following naming scheme:

```text
hosts.backup.YYYYMMDDHHMMSS
```

For example:

```text
hosts.backup.20261125211004
```

Before each content-changing operation, the script creates a backup and rotates older copies.

Backup rotation retains the newest files by modification time.

> Backup names have one-second resolution. Two backups created within the same second can use the same filename. Keep independent copies of important configurations.

## Permissions

The permissions menu uses macOS ACLs.

“Allow editing” adds an explicit write permission for the current user. “Disable editing” removes that specific ACL entry.

This does not:

- Make the file immutable.
- Remove write access granted by other permissions or ACL entries.
- Prevent privileged processes from modifying the file.
- Prevent this script from making changes through `sudo`.

Permission changes are separate from content backups. Do not treat a content restore as an ACL rollback mechanism.

## Validation

The syntax checker is intended to catch common mistakes, including:

- Invalid IPv4 octet values.
- Missing hostnames.
- Address fields that do not match the accepted basic formats.

It ignores blank lines and comments, including inline comments.

Validation has limits:

- IPv6 checking is permissive, not a complete standards-compliant parser.
- Full DNS hostname validation is not implemented.
- Imports and restores do not enforce the presence of default localhost entries.
- Restore operations bypass syntax validation so saved content can be recovered unchanged.
- Duplicate detection compares textual IP–hostname pairs; it does not normalize equivalent IPv6 spellings or hostname case.

Review unfamiliar files before importing them.

## How Changes Are Applied

For content changes, the script generally:

1. Prepares the proposed content.
2. Performs basic syntax validation, where applicable.
3. Backs up the current hosts file.
4. Copies the new content into the destination.
5. Requests a DNS cache refresh.

Reset and restore operations intentionally bypass syntax validation.

Writes are performed in place using `cp`, rather than by replacing the destination with a renamed temporary file.

> Writes are not atomic. An interruption or write failure may leave incomplete contents. Backups provide a recovery path, but do not eliminate this risk.

Avoid running multiple instances or editing the same hosts file simultaneously. The script does not implement locking.

DNS refresh errors are suppressed, so successful file modification does not guarantee that every application immediately uses the new mappings.

## Logging

Operational messages are appended to:

```text
~/.hosts_manager.log
```

The log records events such as backup creation, changes, cancellations, and errors.

It is not a complete audit trail: not every displayed result or command output is written to the log.

## Troubleshooting

### The script refuses to run as root

Launch it as your regular user:

```sh
./hosts_manager_final.sh
```

It will request `sudo` access when needed.

### A write fails despite sudo access

Inspect the file's permissions, ACLs, and flags using menu option `11`.

A file-protection flag or another filesystem restriction may prevent modification. The script does not automatically remove such protections.

### An import fails validation

Run option `7` on the current file to see the style of diagnostics, then inspect the import file for malformed addresses or missing hostnames.

Remember that validation is basic and is not a substitute for reviewing the file.

### A new mapping does not appear to take effect

The script requests a DNS cache refresh after changes, but applications may maintain their own caches or resolve names through other mechanisms.

Confirm that the intended entry was written using option `3`.

## Scope

This project is an interactive local administration tool, not a background service or a complete replacement for a graphical hosts manager.

It does not provide:

- Concurrent-edit protection.
- Atomic writes.
- Full IPv6 or hostname validation.
- Automatic recovery after interrupted writes.
- A dry-run mode.
- Per-entry enable/disable toggles.
- Scheduled backups.

## Project Status

Personal utility, inspired by iHosts.

Review the code and test it on a copy before using it to modify your system configuration.

Built for a straightforward workflow: choose an action, inspect the result, and return to the menu.


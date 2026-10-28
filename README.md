# Mastodon Maintenance Script

A comprehensive maintenance and cleanup script for Mastodon instances. It wraps
`tootctl` with safe defaults, honest error reporting, and explicit guards around
destructive operations.

Everything here has been verified against the Mastodon CLI source at **v4.7.3**
(`lib/mastodon/cli/*.rb`). Note that the published `tootctl` documentation lags
the source in several places — see [Version Support](#-version-support).

## 📋 Table of Contents

- [🚀 Features](#-features)
- [📋 Prerequisites](#-prerequisites)
- [🛠️ Installation](#️-installation)
- [📖 Usage](#-usage)
- [🔧 Available Operations](#-available-operations)
- [⚙️ Configuration](#️-configuration)
- [🛡️ Safety Features](#️-safety-features)
- [📊 Logging and Output](#-logging-and-output)
- [🚨 Destructive Operations](#-destructive-operations)
- [🔍 Monitoring and Health](#-monitoring-and-health)
- [🧩 Version Support](#-version-support)
- [🤝 Contributing](#-contributing)
- [📄 License](#-license)
- [🔄 Version History](#-version-history)

## 🚀 Features

- ✅ Safe defaults for every operation
- ✅ Honest exit codes — a failed step makes the run fail
- ✅ `--dry-run` with real previews where Mastodon supports them
- ✅ Explicit confirmation gate for destructive operations
- ✅ Run locking so overlapping cron jobs cannot collide
- ✅ Per-command error attribution for domain purges
- ✅ Storage-driver detection before orphan media removal
- ✅ Version and `RAILS_ENV` checks at startup

## 📋 Prerequisites

- **Mastodon**: v4.7.3 or newer (tested against 4.7.3)
- **Bash**: 4.4 or newer
  (4.4 is required for `${#array[@]}` on an empty array under `set -u`)
- **Required commands**: `rails`, `tootctl`
- **Optional**: `stdbuf` (unbuffered output), `flock` (run locking)
- **Permissions**: run from your Mastodon installation directory
- **Environment**: `RAILS_ENV` is set to `production` automatically if unset

## 🛠️ Installation

1. **Download the script**

   ```bash
   curl -fsSLO https://raw.githubusercontent.com/johndotpub/mastodon-maintenance/main/clean.sh
   chmod +x clean.sh
   ```

2. **Verify it runs** (works outside a Mastodon directory)

   ```bash
   ./clean.sh --version
   ./clean.sh --help
   ```

3. **Run from your Mastodon directory**

   ```bash
   cd /path/to/your/mastodon/installation
   /path/to/clean.sh --system-health
   ```

## 📖 Usage

### Basic Operations

```bash
./clean.sh --domains          # Export and purge blocked domains
./clean.sh --accounts         # Cull and prune remote accounts
./clean.sh --media            # Remove old media files
./clean.sh --profile-media    # Remove old profile media
./clean.sh --preview-cards    # Remove old preview cards
./clean.sh --remote-statuses  # Remove old remote statuses
./clean.sh --orphaned-media   # Remove orphaned media
./clean.sh --feeds            # Build all feeds
./clean.sh --clear-cache      # Clear the Redis cache
./clean.sh --elasticsearch    # Elasticsearch maintenance
```

### Combined Operations

```bash
./clean.sh --maintenance      # Standard maintenance
./clean.sh --all-media        # All media operations
./clean.sh --full             # Complete cleanup
```

### Enhanced Operations

```bash
./clean.sh --account-cleanup  # Inactive accounts + cull + prune
./clean.sh --media-audit      # Media stats + orphan preview + cleanup
./clean.sh --domain-audit     # Domain list + health + purge
./clean.sh --system-health    # Info + stats + queue + cache
./clean.sh --deep-cleanup     # Complete cleanup with cache clearing
```

### Previewing Changes

```bash
./clean.sh --dry-run --full
./clean.sh --dry-run --domains
./clean.sh --dry-run --media
```

`--dry-run` behaves in one of two ways depending on the underlying command:

- **Commands with native `--dry-run`** (such as `media remove`, `domains purge`,
  `accounts cull`, `preview_cards remove`) are executed with `--dry-run`, so
  Mastodon itself reports exactly what it would do.
- **Commands without it** (such as `statuses remove`, `search deploy`,
  `cache clear`) are printed and skipped with a notice.

A dry run never writes or deletes files of its own.

### Advanced Options

```bash
# Custom concurrency
./clean.sh --concurrency 8 --domains

# Custom retention
./clean.sh --media-days 60 --profile-media-days 60 --maintenance --yes
./clean.sh --preview-cards-days 45 --statuses-days 60 --maintenance --yes

# Inactive account threshold
./clean.sh --account-cleanup --inactive-days 730 --yes

# Verbose output and file logging
./clean.sh --verbose --maintenance --yes
./clean.sh --log-file --system-health
./clean.sh --log-file /var/log/mm.log --maintenance --yes
```

## 🔧 Available Operations

### Basic Operations

| Operation | Description | Default |
|---|---|---|
| `--domains` | Export and purge blocked domains | — |
| `--accounts` | Cull non-existent accounts, then prune | — |
| `--media` | Remove cached remote media | 90 days |
| `--profile-media` | Remove cached remote avatars and headers | 90 days |
| `--preview-cards` | Remove cached preview card images | 30 days |
| `--remote-statuses` | Remove unreferenced remote statuses | 30 days |
| `--orphaned-media` | Remove media files with no database record | — |
| `--feeds` | Rebuild home and list feeds | — |
| `--clear-cache` | Clear the Redis cache | — |
| `--elasticsearch` | Run `tootctl search deploy` | — |

### Combined Operations

| Operation | Includes |
|---|---|
| `--all-media` | media, profile media, preview cards, orphaned media |
| `--maintenance` | accounts, media, profile media, preview cards, remote statuses, orphaned media, elasticsearch, feeds |
| `--full` | everything in `--maintenance`, plus domains and cache clear |

### Enhanced Operations

| Operation | Includes |
|---|---|
| `--account-cleanup` | inactive account listing and deletion, cull, prune |
| `--media-audit` | media usage stats, orphan preview, orphan removal, media cleanup |
| `--domain-audit` | domain block listing, reachability check, export, purge |
| `--system-health` | instance info, statistics, queue status, cache status |
| `--deep-cleanup` | alias of `--full` |

## ⚙️ Configuration

| Option | Default | Notes |
|---|---|---|
| `--concurrency N` | 16 | 1–32. Mastodon resizes its DB pool to N+1 automatically |
| `--media-days N` | 90 | Media retention |
| `--profile-media-days N` | 90 | Avatar/header retention |
| `--preview-cards-days N` | 30 | Mastodon recommends ≥14 days |
| `--statuses-days N` | 30 | Upstream default is 90 |
| `--inactive-days N` | 365 | Inactive account threshold |
| `--domain-batch N` | 25 | Domains per `tootctl` call |

Media cleanup passes `--keep-interacted` by default, so media attached to
statuses that locals favourited, bookmarked, quoted, replied to, or boosted is
preserved. Disable with `--no-keep-interacted`.

## 🛡️ Safety Features

### Dry-run

See [Previewing Changes](#previewing-changes). Dry runs are the recommended first
step for any operation you have not run before.

### Confirmation gate

Irreversible operations require confirmation. On a TTY you are prompted; in
automation (cron, CI, piped input) you must pass `--yes` explicitly. Without it
the script refuses and exits non-zero rather than proceeding.

### Run locking

Operations use `flock` so two overlapping runs cannot purge or cull
concurrently. If `flock` is unavailable the script warns and continues.

### Failure reporting

Every step reports its own result. A failed step makes the whole operation exit
non-zero, so cron and monitoring see the failure instead of a green light.

### Idempotent previews

`export_domain_blocks` only removes the previous export once it is committed to
writing a new one, so a dry run leaves existing files untouched.

## 📊 Logging and Output

- Colour-coded output: blue for info, green for success, yellow for warnings, red for errors
- All messages carry a timestamp
- `--log-file` writes to `cleanup_<timestamp>.log`, or to the path you supply
- `--verbose` shows the exact command and working directory

Note that `stdbuf` is used for unbuffered output when available. It is not
required, and is absent on macOS by default.

## 🚨 Destructive Operations

These permanently delete data and require `--yes` when stdin is not a TTY:

| Operation | What is destroyed |
|---|---|
| `--domains` | Accounts, statuses, and media for every blocked domain |
| `--full` | Everything above, plus statuses, media, and cache |
| `--deep-cleanup` | Same as `--full` |
| `--domain-audit` | Purges all blocked domains |
| `--account-cleanup` | Deletes local accounts inactive beyond the threshold |
| `--remote-statuses` | Unreferenced remote statuses |
| `--orphaned-media` | Files with no database record |
| `--clear-cache` | Redis cache contents |
| `--elasticsearch` | Search indices may be rebuilt |

Two behaviours are worth understanding before using `--domains`:

- **`--include-subdomains` is opt-in and off by default.** Enabling it purges
  every subdomain of every blocked domain as well.
- **`--purge-domain-blocks` is opt-in and off by default.** By default the
  `DomainBlock` records are kept, which is what prevents the domain from
  re-federating. Enabling this flag deletes the blocks too, which removes that
  protection. Only use it when you intend to stop blocking the domain.

`--domains` also batches domains into single `tootctl` invocations. If a batch
fails, the batch is retried one domain at a time so the failing entries are
identifiable.

## 🔍 Monitoring and Health

```bash
./clean.sh --system-health
```

Reports instance information, statistics, Sidekiq process state, and Redis cache
state. These probes require `sidekiq/api` and handle the pooled Redis cache
store correctly, so they report real values instead of a hardcoded "not
available".

## 🧩 Version Support

- **Minimum**: Mastodon 4.7.3. The script checks this at startup and refuses to
  run on older releases, because several flags it uses do not exist there.
- **Tested**: 4.7.3

The published `tootctl` documentation at <https://docs.joinmastodon.org/admin/tootctl/>
does not yet describe every command and flag present in the source at this
version. Where the two disagree, this script follows the source. Flag and
command availability was checked against `lib/mastodon/cli/*.rb` at tag `v4.7.3`.

## 🤝 Contributing

Contributions are welcome via pull request. For substantial changes, please open
an issue first to discuss the approach.

Before submitting:

```bash
bash -n clean.sh            # syntax check
shellcheck clean.sh         # lint
bats tests/                 # full test suite (no Mastodon required)
./clean.sh --help           # smoke test outside an install
```

The test suite uses stubbed `rails` and `tootctl` binaries under `tests/stubs/`,
so it runs anywhere. CI runs ShellCheck, the Bats suite, and documentation
consistency checks on every push and pull request.

Changes to any `tootctl` invocation must be verified against the Mastodon source
at the supported version, not against the documentation alone.

## 📄 License

This is free and unencumbered software released into the public domain under the
[Unlicense](LICENSE). See the [LICENSE](LICENSE) file for details.

## 🔄 Version History

### v2.0.0

Compatibility and correctness release. **Requires Mastodon 4.7.3 or newer.**
This release contains breaking changes; see below.

- **Breaking** — minimum Mastodon raised from 4.4.2 to 4.7.3, enforced at startup
- **Breaking** — destructive operations require `--yes` when non-interactive
- **Breaking** — `--deep-cleanup` is now an alias of `--full`
- **Breaking** — `--include-subdomains` is now off by default
- Fixed: six `tootctl` subcommands that never existed (`accounts list`,
  `accounts delete --inactive`, `media stats`, `media list-orphans`,
  `domains list`, `domains check`) are replaced with supported commands and
  `rails runner` queries; `--account-cleanup`, `--media-audit`,
  `--domain-audit`, and `--system-health` now function
- Fixed: failures were reported as success — a failed step now fails the run
- Fixed: `--dry-run` without an operation did nothing; it now requires an operation
- Fixed: dry runs wrote and deleted `domain_blocks.txt`
- Fixed: `--include-subdomains` could not be disabled
- Fixed: domain purges ran one Rails boot per domain; now batched
- Fixed: `--help` and `--version` failed outside a Mastodon installation
- Fixed: queue and cache health probes always reported negative results
- Fixed: a documented multi-operation example could never work
- Added: `--yes`, `--purge-domain-blocks`, `--no-keep-interacted`,
  `--inactive-days`, `--domain-batch`
- Added: `RAILS_ENV` defaulting, version gate, `flock` locking
- Added: storage-driver detection before orphan media removal
- Changed: `--concurrency` documented; Mastodon resizes its pool accordingly
- Changed: defaults and documentation corrected to match the code

### v1.0.2

- Added Elasticsearch maintenance operations
- Improved error handling with Rails runner try/catch blocks
- Enhanced configuration validation (concurrency 1–32, retention days 1–365)
- Added comprehensive function documentation
- Added system health check improvements
- Improved README with better examples

### v1.0.1

- Simplified script architecture for improved reliability and easier maintenance

### v1.0.0

- Initial release with comprehensive maintenance operations

---

Made with ❤️ for the Mastodon community.

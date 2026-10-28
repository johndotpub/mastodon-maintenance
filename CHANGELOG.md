# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.0.0] - 2026-10-27

Correctness release. Every `tootctl` invocation was re-verified against the
Mastodon CLI source at tag `v4.7.3` (`lib/mastodon/cli/*.rb`). The published
`tootctl` documentation does not yet cover every command and flag present in
that source; where the two disagree, this release follows the source.

### Changed

- **Minimum Mastodon is now 4.7.3**, up from 4.4.2, and is enforced at startup
  with a clear error instead of failing partway through an operation. This is a
  breaking change for older installations.
- **Destructive operations require `--yes` when stdin is not a TTY.** On an
  interactive terminal the script prompts. In cron or CI it refuses and exits
  non-zero. Existing scheduled jobs need `--yes` added once.
- **`--include-subdomains` is now off by default.** It previously defaulted to
  on and could not be disabled, so a plain `--domains` run also purged every
  subdomain of every blocked domain.
- **`--deep-cleanup` is now an alias of `--full`.** The two previously differed
  without either being a genuine superset; `--full` now includes cache clearing.
- `--log-file` accepts an optional path argument.
- Retention validation widened from 1–365 to 1–3650 days.
- `--help` text and the README now match actual behaviour.

### Added

- `--yes` for non-interactive confirmation of destructive operations.
- `--purge-domain-blocks` to also delete `DomainBlock` rows while purging.
  Off by default, because those rows are what prevent re-federation.
- `--no-keep-interacted` to opt out of protecting locally-engaged media.
  `--keep-interacted` is applied by default when removing media.
- `--inactive-days` to configure the inactive-account threshold (default 365).
- `--domain-batch` to control how many domains are passed per `tootctl` call.
- `RAILS_ENV` defaults to `production` when unset, with a warning if it is
  set to something else.
- Startup version gate against the minimum supported Mastodon release.
- `flock`-based run locking so overlapping cron jobs cannot collide.
- Storage-driver detection before orphaned media removal.
- `CHANGELOG.md`, backfilled from earlier releases.

### Fixed

- **Six `tootctl` subcommands that never existed have been replaced.**
  `accounts list`, `accounts delete --inactive`, `media stats`,
  `media list-orphans`, `domains list`, and `domains check` are absent from
  Mastodon's CLI at both 4.4.2 and 4.7.3. They are replaced with supported
  commands (`media usage`, `media remove-orphans --dry-run`) and `rails runner`
  queries. As a result `--account-cleanup`, `--media-audit`, `--domain-audit`,
  and `--system-health` now work.
- **Failures were reported as success.** The operation dispatcher was wrapped in
  an `if`, which suspends `set -e` for the entire call tree, and each group
  returned only its last command's status. A composite operation could fail
  several steps and still exit 0. Each step now reports its own result and any
  failure fails the run.
- **`--dry-run` with no operation selected did nothing** while exiting 0, making
  the documented first-run example a no-op.
- **`--dry-run` still mutated the filesystem.** Domain block export bypassed the
  dry-run gate and deleted then rewrote `domain_blocks.txt`. Export is now
  correctly skipped, and the previous file is only removed once a new export is
  committed.
- **Dry-run previews were dead code.** `purge_domains` appended `--dry-run` to
  the command, but the generic gate skipped execution before it could run.
  Commands with native `--dry-run` support now execute with it and produce a real
  preview; commands without it are printed and skipped with a notice.
- **`--help` and `--version` failed outside a Mastodon installation**, because
  prerequisite checks ran before argument parsing.
- **Domain purges ran one full Rails boot per domain**, taking hours on large
  blocklists. Domains are now batched, with per-domain retry only when a batch
  fails, so failures remain attributable.
- **Domain entries were parsed with `echo | cut | xargs`**, which mangles quotes
  and backslashes. Replaced with parameter expansion.
- **Queue and cache health probes always reported negative results.**
  `Sidekiq::ProcessSet` requires `sidekiq/api`, which is not loaded by a bare
  `require 'sidekiq'`. `Rails.cache.redis` returns a `ConnectionPool`, which has
  no `#ping`, and the error was silently rescued into a hardcoded `false`.
  Both probes now report real values.
- **A documented example could never work.**
  `./clean.sh --accounts --orphaned-media` always errored, because only one
  operation may be selected. The example has been removed.
- **`stdbuf` was an undeclared hard dependency.** It is now optional and detected
  at startup rather than failing every operation with exit 127.
- **`error_count` was computed and then ignored**, so a domain purge where every
  domain failed still returned success.
- **Arithmetic counters used `((x++))`**, which returns non-zero on the 0→1
  increment and aborts under `set -e`. Replaced with explicit assignment. This
  was previously masked by the dispatcher bug above.
- **`elasticsearch_maintenance` ran unconditionally**, failing on instances
  without Elasticsearch enabled. It is now gated on `ES_ENABLED=true`.
- **`tootctl search deploy` is never run in dry-run mode.** It has no `--dry-run`
  support and erases index data when the index specification has changed.
- **`--orphaned-media` failed on unsupported storage drivers.** `remove-orphans`
  only implements S3 and filesystem storage and fails hard on fog and Azure. The
  driver is now detected and the step skipped with a warning.
- **The Rails error message during domain export was discarded** by `2>/dev/null`.
- **README code fences were unbalanced.** The Basic Operations block was never
  closed, so the Combined Operations section rendered inside it.
- **README and LICENSE disagreed on licensing.** The README claimed MIT while
  the LICENSE file is the Unlicense. The README now matches the LICENSE.

### Notes

- `--concurrency` still defaults to 16. Mastodon resizes its connection pool to
  `concurrency + 1` for these commands, so this is safe, but it remains heavier
  than the upstream default of 5.
- `--preview-cards-days` remains at 30. Mastodon recommends not pruning preview
  cards newer than 14 days, so 30 is within the safe range, though more
  aggressive than the upstream default of 180.
- `--statuses-days` remains at 30, below the upstream default of 90.

## [1.0.2] - 2025-08-03

### Added

- Elasticsearch maintenance operations via `tootctl search deploy`
- System health check improvements
- Comprehensive function documentation
- README improvements with additional examples

### Changed

- Improved error handling with Rails runner try/catch blocks
- Enhanced configuration validation (concurrency 1–32, retention days 1–365)
- Enhanced error messages and user guidance

## [1.0.1] - 2025-08-03

### Changed

- Simplified script architecture for improved reliability and easier maintenance

## [1.0.0] - 2025-08-03

### Added

- Initial release with comprehensive maintenance operations: domain purging,
  account cleanup, media cleanup, and feed rebuilding

[Unreleased]: https://github.com/johndotpub/mastodon-maintenance/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/johndotpub/mastodon-maintenance/releases/tag/v2.0.0
[1.0.2]: https://github.com/johndotpub/mastodon-maintenance/compare/v1.0.1...v1.0.2

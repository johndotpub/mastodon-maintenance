#!/usr/bin/env bats
#
# Bats test suite for clean.sh
#
# Runs against stubbed `rails` and `tootctl` binaries so no Mastodon
# installation is required.
#
# Run: bats tests/clean.bats
#
bats_require_minimum_version 1.5.0

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    SCRIPT="$REPO_ROOT/clean.sh"
    STUBS="$BATS_TEST_DIRNAME/stubs"

    TEST_TMP="$(mktemp -d)"
    export PATH="$TEST_TMP/bin:$PATH"
    mkdir -p "$TEST_TMP/bin"
    cp "$STUBS/rails" "$STUBS/tootctl" "$TEST_TMP/bin/"
    chmod +x "$TEST_TMP/bin/rails" "$TEST_TMP/bin/tootctl"

    cd "$TEST_TMP" || return 1
}

teardown() {
    rm -rf "$TEST_TMP"
}

# Run clean.sh in the isolated directory, capturing combined output.
run_clean() {
    run bash -c "bash '$SCRIPT' \"\$@\" > '$TEST_TMP/out.log' 2>&1 < /dev/null; echo \"rc=\$?\"" -- "$@"
    RC=$(sed -n 's/^rc=//p' <<< "${output}")
    OUT="$(cat "$TEST_TMP/out.log")"
}

# ---------------------------------------------------------------------------
# Informational flags — must work outside a Mastodon installation
# ---------------------------------------------------------------------------

@test "help exits 0 outside an install" {
    run_clean --help
    [ "$RC" -eq 0 ]
}

@test "version exits 0 outside an install" {
    run_clean --version
    [ "$RC" -eq 0 ]
}

@test "version reports the minimum supported Mastodon release" {
    run_clean --version
    [[ "$OUT" == *"Minimum Mastodon: 4.7.3"* ]]
}

@test "list-operations exits 0" {
    run_clean --list-operations
    [ "$RC" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------

@test "unknown flag exits 1" {
    run_clean --not-a-real-flag
    [ "$RC" -eq 1 ]
    [[ "$OUT" == *"Unknown option"* ]]
}

@test "two operations are rejected" {
    run_clean --accounts --media
    [ "$RC" -eq 1 ]
    [[ "$OUT" == *"Only one operation can be selected"* ]]
}

@test "non-numeric concurrency is rejected" {
    run_clean --concurrency abc --media
    [ "$RC" -eq 1 ]
    [[ "$OUT" == *"Invalid value for --concurrency"* ]]
}

@test "concurrency outside range is rejected" {
    run_clean --concurrency 99 --media
    [ "$RC" -eq 1 ]
    [[ "$OUT" == *"Concurrency must be between 1 and 32"* ]]
}

# ---------------------------------------------------------------------------
# Failure propagation — the core regression
# ---------------------------------------------------------------------------

@test "composite operation with a failing step exits non-zero" {
    export MM_STUB_FAIL="accounts cull"
    run_clean --maintenance --yes
    [ "$RC" -eq 1 ]
}

@test "composite operation reports incomplete rather than success" {
    export MM_STUB_FAIL="accounts cull"
    run_clean --maintenance --yes
    [[ "$OUT" == *"did not complete successfully"* ]]
    [[ "$OUT" != *"Cleanup completed successfully!"* ]]
}

@test "composite operation with no failures exits 0" {
    run_clean --maintenance --yes
    [ "$RC" -eq 0 ]
    [[ "$OUT" == *"Cleanup completed successfully!"* ]]
}

@test "single failing operation exits non-zero" {
    export MM_STUB_FAIL="feeds build"
    run_clean --feeds
    [ "$RC" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Domain purge
# ---------------------------------------------------------------------------

@test "domain purge failure exits non-zero" {
    export MM_STUB_FAIL="domains purge"
    run_clean --domains --yes
    [ "$RC" -eq 1 ]
}

@test "failed batch falls back to per-domain retry" {
    export MM_STUB_FAIL="domains purge"
    run_clean --domains --yes
    [[ "$OUT" == *"retrying individually"* ]]
}

@test "successful domain purge exits 0" {
    run_clean --domains --yes
    [ "$RC" -eq 0 ]
}

@test "subdomains are disabled by default" {
    run_clean --domains --yes --dry-run
    [[ "$OUT" == *"Include subdomains:    false"* ]]
}

@test "include-subdomains can be enabled" {
    run_clean --domains --yes --dry-run --include-subdomains
    [[ "$OUT" == *"--include-subdomains"* ]]
}

@test "purge-domain-blocks is opt-in" {
    run_clean --domains --yes --dry-run
    [[ "$OUT" != *"--purge-domain-blocks"* ]]
}

@test "purge-domain-blocks is passed when requested" {
    run_clean --domains --yes --dry-run --purge-domain-blocks
    [[ "$OUT" == *"--purge-domain-blocks"* ]]
}

# ---------------------------------------------------------------------------
# Dry-run behaviour
# ---------------------------------------------------------------------------

@test "dry run does not write domain_blocks.txt" {
    run_clean --domains --yes --dry-run
    [ ! -f "$TEST_TMP/domain_blocks.txt" ]
}

@test "dry run leaves an existing export untouched" {
    echo "original" > "$TEST_TMP/domain_blocks.txt"
    run_clean --domains --yes --dry-run
    [ "$(cat "$TEST_TMP/domain_blocks.txt")" = "original" ]
}

@test "dry run passes --dry-run through to commands that support it" {
    run_clean --media --dry-run
    [[ "$OUT" == *"--dry-run"* ]]
}

@test "dry run skips commands without native dry-run support" {
    run_clean --clear-cache --dry-run
    [[ "$OUT" == *"no native --dry-run support"* ]]
}

@test "dry run exits 0 for a command without dry-run support" {
    run_clean --clear-cache --dry-run
    [ "$RC" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Confirmation gate
# ---------------------------------------------------------------------------

@test "destructive operation refuses without --yes when non-interactive" {
    run_clean --media
    [ "$RC" -eq 1 ]
    [[ "$OUT" == *"Refusing destructive action without --yes"* ]]
}

@test "destructive operation proceeds with --yes" {
    run_clean --media --yes
    [ "$RC" -eq 0 ]
}

@test "dry run needs no --yes" {
    run_clean --media --dry-run
    [ "$RC" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Media handling
# ---------------------------------------------------------------------------

@test "media removal preserves locally-interacted media by default" {
    run_clean --media --dry-run
    [[ "$OUT" == *"--keep-interacted"* ]]
}

@test "keep-interacted can be disabled" {
    run_clean --media --dry-run --no-keep-interacted
    [[ "$OUT" != *"--keep-interacted"* ]]
}

@test "media removal honours custom retention" {
    run_clean --media-days 45 --media --dry-run
    [[ "$OUT" == *"--days 45"* ]]
}

# ---------------------------------------------------------------------------
# Storage driver guard
# ---------------------------------------------------------------------------

@test "unsupported storage driver is skipped, not fatal" {
    export MM_STUB_STORAGE=azure
    run_clean --orphaned-media --yes
    [ "$RC" -eq 0 ]
    [[ "$OUT" == *"is not supported by tootctl media remove-orphans"* ]]
}

@test "filesystem storage proceeds with orphan removal" {
    export MM_STUB_STORAGE=filesystem
    run_clean --orphaned-media --yes
    [ "$RC" -eq 0 ]
    [[ "$OUT" == *"remove-orphans"* ]]
}

# ---------------------------------------------------------------------------
# Elasticsearch gating
# ---------------------------------------------------------------------------

@test "elasticsearch maintenance is skipped when ES_ENABLED is false" {
    export MM_STUB_ES=false
    run_clean --elasticsearch --yes
    [ "$RC" -eq 0 ]
    [[ "$OUT" == *"ES_ENABLED is not 'true'"* ]]
}

@test "elasticsearch maintenance runs when ES_ENABLED is true" {
    export MM_STUB_ES=true
    run_clean --elasticsearch --yes
    [[ "$OUT" == *"search deploy"* ]]
}

# ---------------------------------------------------------------------------
# Health probes
# ---------------------------------------------------------------------------

@test "system-health exits 0" {
    run_clean --system-health
    [ "$RC" -eq 0 ]
}

@test "queue probe reports a Sidekiq process count" {
    run_clean --system-health
    [[ "$OUT" == *"Sidekiq processes: 2"* ]]
}

@test "cache probe reports real Redis connectivity" {
    run_clean --system-health
    [[ "$OUT" == *"Redis connected: true"* ]]
}

@test "cache probe is not hardcoded to false" {
    run_clean --system-health
    [[ "$OUT" != *"Redis connected: false"* ]]
}

# ---------------------------------------------------------------------------
# Version gate
# ---------------------------------------------------------------------------

@test "release below the minimum is rejected" {
    export MM_STUB_VERSION=4.4.2
    run_clean --feeds
    [ "$RC" -eq 1 ]
    [[ "$OUT" == *"older than the supported minimum 4.7.3"* ]]
}

@test "release at the minimum is accepted" {
    export MM_STUB_VERSION=4.7.3
    run_clean --feeds
    [ "$RC" -eq 0 ]
}

@test "release above the tested version warns but proceeds" {
    export MM_STUB_VERSION=4.8.0
    run_clean --feeds
    [ "$RC" -eq 0 ]
    [[ "$OUT" == *"newer than the tested version"* ]]
}

# ---------------------------------------------------------------------------
# Shell safety
# ---------------------------------------------------------------------------

@test "counters do not abort under set -e" {
    run_clean --domains --yes --dry-run
    [ "$RC" -eq 0 ]
}

@test "RAILS_ENV defaults to production" {
    run_clean --system-health
    [[ "$OUT" == *"RAILS_ENV: production"* ]]
}

@test "script parses cleanly" {
    run bash -n "$SCRIPT"
    [ "$status" -eq 0 ]
}

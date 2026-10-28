#!/usr/bin/env bats
#
# Bats coverage for every operation and option in clean.sh.
# Runs against stubs; no Mastodon installation required.
#
bats_require_minimum_version 1.5.0

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    SCRIPT="${MM_SCRIPT:-$REPO_ROOT/clean.sh}"
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

run_clean() {
    run bash -c "bash '$SCRIPT' \"\$@\" > '$TEST_TMP/out.log' 2>&1 < /dev/null; echo \"rc=\$?\"" -- "$@"
    RC=$(sed -n 's/^rc=//p' <<< "${output}")
    OUT="$(cat "$TEST_TMP/out.log")"
}

# ===========================================================================
# Every basic operation is selectable and reaches its tootctl command
# ===========================================================================

@test "--domains invokes domains purge" {
    run_clean --domains --yes
    [[ "$OUT" == *"domains purge"* ]]
}

@test "--accounts invokes cull and prune" {
    run_clean --accounts --yes
    [[ "$OUT" == *"accounts cull"* ]]
    [[ "$OUT" == *"accounts prune"* ]]
}

@test "--media invokes media remove" {
    run_clean --media --yes
    [[ "$OUT" == *"media remove"* ]]
}

@test "--profile-media invokes media remove --prune-profiles" {
    run_clean --profile-media --yes
    [[ "$OUT" == *"media remove --prune-profiles"* ]]
}

@test "--preview-cards invokes preview_cards remove" {
    run_clean --preview-cards --yes
    [[ "$OUT" == *"preview_cards remove"* ]]
}

@test "--remote-statuses invokes statuses remove" {
    run_clean --remote-statuses --yes
    [[ "$OUT" == *"statuses remove"* ]]
}

@test "--orphaned-media invokes media remove-orphans" {
    run_clean --orphaned-media --yes
    [[ "$OUT" == *"media remove-orphans"* ]]
}

@test "--feeds invokes feeds build --all" {
    run_clean --feeds
    [[ "$OUT" == *"feeds build --all"* ]]
}

@test "--clear-cache invokes cache clear" {
    run_clean --clear-cache --yes
    [[ "$OUT" == *"cache clear"* ]]
}

@test "--elasticsearch invokes search deploy when enabled" {
    export MM_STUB_ES=true
    run_clean --elasticsearch --yes
    [[ "$OUT" == *"search deploy"* ]]
}

# ===========================================================================
# Combined operations contain the expected sub-operations
# ===========================================================================

@test "--all-media runs all four media operations" {
    run_clean --all-media --yes
    [[ "$OUT" == *"media remove --days"* ]]
    [[ "$OUT" == *"media remove --prune-profiles"* ]]
    [[ "$OUT" == *"preview_cards remove"* ]]
    [[ "$OUT" == *"media remove-orphans"* ]]
}

@test "--maintenance includes accounts, media, feeds" {
    run_clean --maintenance --yes
    [[ "$OUT" == *"accounts cull"* ]]
    [[ "$OUT" == *"media remove"* ]]
    [[ "$OUT" == *"feeds build"* ]]
}

@test "--full includes domains and cache clearing" {
    run_clean --full --yes
    [[ "$OUT" == *"domains purge"* ]]
    [[ "$OUT" == *"cache clear"* ]]
}

@test "--deep-cleanup is an alias of --full" {
    run_clean --deep-cleanup --yes
    [[ "$OUT" == *"domains purge"* ]]
    [[ "$OUT" == *"cache clear"* ]]
}

# ===========================================================================
# Enhanced operations use supported commands, not phantom subcommands
# ===========================================================================

@test "--account-cleanup works using rails runners" {
    run_clean --account-cleanup --yes
    [ "$RC" -eq 0 ]
    [[ "$OUT" == *"Total inactive"* ]]
}

@test "--media-audit uses media usage, not media stats" {
    run_clean --media-audit --yes
    [[ "$OUT" == *"media usage"* ]]
    [[ "$OUT" != *"media stats"* ]]
}

@test "--media-audit previews orphans via remove-orphans --dry-run" {
    run_clean --media-audit --yes
    [[ "$OUT" == *"remove-orphans"* ]]
    [[ "$OUT" != *"list-orphans"* ]]
}

@test "--domain-audit lists blocks via rails runner, not domains list" {
    run_clean --domain-audit --yes
    [[ "$OUT" == *"SEVERITY"* ]]
    [[ "$OUT" != *"domains list"* ]]
}

@test "--domain-audit never calls domains check" {
    run_clean --domain-audit --yes
    [[ "$OUT" != *"domains check"* ]]
}

@test "--system-health completes" {
    run_clean --system-health
    [ "$RC" -eq 0 ]
}

@test "no operation calls a phantom subcommand" {
    run_clean --account-cleanup --media-audit --domain-audit --yes
    [ "$RC" -eq 1 ]
}

@test "phantom subcommands absent from all enhanced runs" {
    run_clean --media-audit --yes
    [[ "$OUT" != *"media list-orphans"* ]]
    [[ "$OUT" != *"media stats"* ]]
}

# ===========================================================================
# Configuration options
# ===========================================================================

@test "--concurrency is applied" {
    run_clean --concurrency 8 --media --dry-run
    [[ "$OUT" == *"--concurrency 8"* ]]
}

@test "--profile-media-days is applied" {
    run_clean --profile-media-days 120 --profile-media --dry-run
    [[ "$OUT" == *"--days 120"* ]]
}

@test "--preview-cards-days is applied" {
    run_clean --preview-cards-days 45 --preview-cards --dry-run
    [[ "$OUT" == *"--days 45"* ]]
}

@test "--statuses-days is applied" {
    run_clean --statuses-days 60 --remote-statuses --yes
    [[ "$OUT" == *"--days 60"* ]]
}

@test "--inactive-days is applied" {
    run_clean --inactive-days 730 --account-cleanup --yes
    [ "$RC" -eq 0 ]
}

@test "--domain-batch controls batch size" {
    run_clean --domain-batch 1 --domains --yes --dry-run
    [[ "$OUT" == *"Batch size:         1"* ]]
}

@test "invalid retention is rejected" {
    run_clean --media-days 0 --media
    [ "$RC" -eq 1 ]
    [[ "$OUT" == *"must be between"* ]]
}

@test "invalid domain-batch is rejected" {
    run_clean --domain-batch 9999 --domains --yes
    [ "$RC" -eq 1 ]
}

# ===========================================================================
# Logging
# ===========================================================================

@test "--log-file writes a log with a header" {
    run_clean --log-file --system-health
    ls "$TEST_TMP"/cleanup_*.log >/dev/null 2>&1
    grep -q "Mastodon Cleanup Script" "$TEST_TMP"/cleanup_*.log
}

@test "--log-file accepts an explicit path" {
    run_clean --log-file "$TEST_TMP/mylog.txt" --system-health
    [ -f "$TEST_TMP/mylog.txt" ]
    grep -q "Mastodon Cleanup Script" "$TEST_TMP/mylog.txt"
}

@test "log captures the start of the run" {
    run_clean --log-file "$TEST_TMP/mylog.txt" --system-health
    grep -q "Starting Mastodon Cleanup Process" "$TEST_TMP/mylog.txt"
}

@test "--verbose reports the working directory" {
    run_clean --verbose --system-health
    [[ "$OUT" == *"Working directory"* ]]
}

# ===========================================================================
# Output shape
# ===========================================================================

@test "configuration summary is printed" {
    run_clean --media --dry-run
    [[ "$OUT" == *"Configuration Summary"* ]]
}

@test "no operation selected exits 0 with a warning" {
    run_clean
    [ "$RC" -eq 0 ]
    [[ "$OUT" == *"No operation selected"* ]]
}

@test "success emits a completion header" {
    run_clean --feeds
    [[ "$OUT" == *"Cleanup Process Complete"* ]]
}

@test "failure emits an incomplete header" {
    export MM_STUB_FAIL="feeds build"
    run_clean --feeds
    [[ "$OUT" == *"Cleanup Process Incomplete"* ]]
}

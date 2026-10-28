#!/usr/bin/env bash
#
# Mastodon Maintenance Script
# https://github.com/johndotpub/mastodon-maintenance
#
# Copyright waived via the Unlicense. See LICENSE.
#
set -euo pipefail

# =============================================================================
# Mastodon Instance Cleanup Script
# =============================================================================
# Performs cleanup and maintenance operations on a Mastodon instance:
# domain purging, account management, media cleanup, and feed rebuilding.
#
# Usage: ./clean.sh [OPTIONS] [OPERATION]
#
# Options:
#   --dry-run                Preview only. Commands with native --dry-run support
#                            are executed with it; others are skipped with a notice.
#   --yes                    Required for destructive operations when not on a TTY.
#   --include-subdomains     Include subdomains when purging domains (opt-in).
#   --concurrency N          Concurrency level (default: 16)
#   --verbose                Verbose output
#   --log-file [PATH]        Log to file (default: cleanup_<timestamp>.log)
#   --help                   Show this help message
#   --version                Show version information
#
# Operations:
#   Basic:
#     --domains              Export and purge blocked domains
#     --accounts             Clean up accounts (cull + prune)
#     --media                Remove old media files
#     --profile-media        Remove old profile media
#     --preview-cards        Remove old preview cards
#     --remote-statuses      Remove old remote statuses
#     --orphaned-media       Remove orphaned media
#     --feeds                Build all feeds
#     --clear-cache          Clear Redis cache
#     --elasticsearch        Elasticsearch maintenance
#
#   Combined:
#     --all-media            All media operations
#     --maintenance          Standard maintenance operations
#     --full                 Complete cleanup (all operations)
#
#   Enhanced:
#     --account-cleanup      Enhanced account cleanup (inactive + cull + prune)
#     --media-audit          Media audit (stats + orphans + cleanup)
#     --domain-audit         Domain audit (list + check + purge)
#     --system-health        System health check (info + stats + queue + cache)
#     --deep-cleanup         Complete cleanup with cache clearing
#
# Examples:
#   ./clean.sh --help
#   ./clean.sh --dry-run --full
#   ./clean.sh --domains
#   ./clean.sh --media --verbose
#   ./clean.sh --concurrency 8 --domains
#   ./clean.sh --maintenance --yes --log-file
# =============================================================================

readonly SCRIPT_NAME="Mastodon Cleanup Script"
readonly SCRIPT_VERSION="2.0.0"
readonly SCRIPT_AUTHOR="@johndotpub@rewt.link"

# Minimum supported Mastodon version. Verified against lib/mastodon/cli/*.rb
# at this tag; flags used below (e.g. media remove --keep-interacted,
# domains purge --include-subdomains/--purge-domain-blocks) exist here.
readonly MIN_MASTODON_VERSION="4.7.3"
readonly TESTED_MASTODON_VERSION="4.7.3"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# Default configuration
readonly DEFAULT_CONCURRENCY=16
readonly DEFAULT_MEDIA_DAYS=90
readonly DEFAULT_PROFILE_MEDIA_DAYS=90
readonly DEFAULT_PREVIEW_CARDS_DAYS=30
readonly DEFAULT_STATUSES_DAYS=30
readonly DEFAULT_INACTIVE_DAYS=365
readonly DEFAULT_DOMAIN_BATCH=25
DOMAIN_BLOCKS_FILE="domain_blocks.txt"
readonly LOCKFILE="${TMPDIR:-/tmp}/mastodon-maintenance.lock"

# =============================================================================
# Global state
# =============================================================================

DRY_RUN=false
ASSUME_YES=false
INCLUDE_SUBDOMAINS=false
PURGE_DOMAIN_BLOCKS=false
KEEP_INTERACTED=true
CONCURRENCY=$DEFAULT_CONCURRENCY
MEDIA_DAYS=$DEFAULT_MEDIA_DAYS
PROFILE_MEDIA_DAYS=$DEFAULT_PROFILE_MEDIA_DAYS
PREVIEW_CARDS_DAYS=$DEFAULT_PREVIEW_CARDS_DAYS
STATUSES_DAYS=$DEFAULT_STATUSES_DAYS
INACTIVE_DAYS=$DEFAULT_INACTIVE_DAYS
DOMAIN_BATCH=$DEFAULT_DOMAIN_BATCH
VERBOSE=false
LOG_TO_FILE=false
LOG_FILE=""
SELECTED_OPERATION=""

# Step accounting. Every operation reports its own result; nothing is inferred.

# stdbuf is optional. When present it makes tootctl output unbuffered; when
# absent we simply run the command directly rather than failing at 127.
STDBUF=()
if command -v stdbuf >/dev/null 2>&1; then
    STDBUF=(stdbuf -oL)
fi

# =============================================================================
# Logging
# =============================================================================

print_log() {
    local level="$1"
    local color="$2"
    local message="$3"
    local timestamp

    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${color}[${timestamp}] [${level}]${NC} $message"

    if [[ "$LOG_TO_FILE" == "true" && -n "$LOG_FILE" ]]; then
        echo "[${timestamp}] [${level}] $message" >> "$LOG_FILE"
    fi
}

print_info()    { print_log "INFO"    "$BLUE"   "$1"; }
print_success() { print_log "SUCCESS" "$GREEN"  "$1"; }
print_warning() { print_log "WARNING" "$YELLOW" "$1"; }
print_error()   { print_log "ERROR"   "$RED"    "$1" >&2; }

print_header() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo -e "${PURPLE}================================${NC}"
    echo -e "${PURPLE}[${timestamp}] $1${NC}"
    echo -e "${PURPLE}================================${NC}"

    if [[ "$LOG_TO_FILE" == "true" && -n "$LOG_FILE" ]]; then
        echo "[${timestamp}] [HEADER] $1" >> "$LOG_FILE"
    fi
}

# =============================================================================
# Utilities
# =============================================================================

command_exists() { command -v "$1" >/dev/null 2>&1; }

is_numeric() { [[ "$1" =~ ^[0-9]+$ ]]; }

# Version comparison: returns 0 if $1 >= $2
# Mastodon::Version.to_s can append a prerelease and/or build metadata
# (e.g. "4.7.3+custom", "4.8.0-beta1"), which would otherwise be evaluated as
# identifiers in arithmetic context and abort under `set -u`. Strip suffixes and
# coerce every component to a number before comparing.
version_ge() {
    local v1="${1%%[-+]*}" v2="${2%%[-+]*}"
    local -a a b
    IFS=. read -r -a a <<< "$v1"
    IFS=. read -r -a b <<< "$v2"
    local i x y
    for i in 0 1 2; do
        x="${a[$i]:-0}"
        y="${b[$i]:-0}"
        [[ "$x" =~ ^[0-9]+$ ]] || x=0
        [[ "$y" =~ ^[0-9]+$ ]] || y=0
        if ((x > y)); then return 0; fi
        if ((x < y)); then return 1; fi
    done
    return 0
}

validate_configuration() {
    local var value
    if ((CONCURRENCY < 1 || CONCURRENCY > 32)); then
        print_error "Concurrency must be between 1 and 32 (current: $CONCURRENCY)"
        return 1
    fi

    for var in MEDIA_DAYS PROFILE_MEDIA_DAYS PREVIEW_CARDS_DAYS STATUSES_DAYS INACTIVE_DAYS; do
        value="${!var}"
        if ((value < 1 || value > 3650)); then
            print_error "$var must be between 1 and 3650 days (current: $value)"
            return 1
        fi
    done

    if ((DOMAIN_BATCH < 1 || DOMAIN_BATCH > 500)); then
        print_error "Domain batch size must be between 1 and 500 (current: $DOMAIN_BATCH)"
        return 1
    fi

    return 0
}

# Confirmation gate for irreversible operations.
# Dry runs never need confirmation. On a TTY the operator is prompted; in
# automation --yes must be supplied explicitly.
confirm_destructive() {
    local action="$1"

    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi

    if [[ "$ASSUME_YES" == "true" ]]; then
        print_warning "Proceeding with destructive action (--yes supplied): $action"
        return 0
    fi

    if [[ -t 0 ]]; then
        print_warning "About to: $action"
        print_warning "This cannot be undone. Type 'yes' to continue."
        local reply=""
        read -r reply || true
        if [[ "$reply" == "yes" ]]; then
            return 0
        fi
        print_error "Confirmation declined"
        return 1
    fi

    print_error "Refusing destructive action without --yes (non-interactive): $action"
    return 1
}

# =============================================================================
# Command execution
# =============================================================================
#
# Two execution paths:
#
#   run_native_dry_run  - the underlying tool supports --dry-run, so we pass it
#                         through and let tootctl produce a real preview.
#   run_no_dry_run      - the tool has no preview mode, so a dry run prints the
#                         command and skips execution.
#
# Both return 0 on success and 1 on failure; nothing swallows the status.

run_native_dry_run() {
    local description="$1"
    shift

    local -a args=( "$@" )

    if [[ "$DRY_RUN" == "true" ]]; then
        args+=(--dry-run)
    fi

    print_info "Executing: $description"

    if [[ "$VERBOSE" == "true" ]]; then
        print_info "Command: ${args[*]}"
        print_info "Working directory: $(pwd)"
    fi

    local exit_code=0
    if "${args[@]}" </dev/null 2>&1; then
        print_success "Completed: $description"
        return 0
    else
        exit_code=$?
        print_error "Failed: $description (exit code: $exit_code)"
        return 1
    fi
}

run_no_dry_run() {
    local description="$1"
    shift

    local -a args=( "$@" )

    print_info "Executing: $description"

    if [[ "$DRY_RUN" == "true" ]]; then
        print_warning "DRY RUN: skipped (no native --dry-run support): ${args[*]}"
        return 0
    fi

    if [[ "$VERBOSE" == "true" ]]; then
        print_info "Command: ${args[*]}"
        print_info "Working directory: $(pwd)"
    fi

    local exit_code=0
    if "${args[@]}" </dev/null 2>&1; then
        print_success "Completed: $description"
        return 0
    else
        exit_code=$?
        print_error "Failed: $description (exit code: $exit_code)"
        return 1
    fi
}

# =============================================================================
# Prerequisites
# =============================================================================

check_prerequisites() {
    print_header "Checking Prerequisites"

    local missing=()

    for cmd in rails tootctl; do
        if ! command_exists "$cmd"; then
            missing+=("$cmd")
        fi
    done

    if (( ${#missing[@]} > 0 )); then
        print_error "Missing required commands: ${missing[*]}"
        print_error "Run this script from your Mastodon installation directory."
        print_error "If using bundler, ensure the bundle is active (bundle exec)."
        exit 1
    fi

    # RAILS_ENV must be explicit. Without it tootctl defaults to development,
    # where production gems are absent, producing "uninitialized constant"
    # errors rather than a clear failure.
    if [[ -z "${RAILS_ENV:-}" ]]; then
        export RAILS_ENV="production"
        print_info "RAILS_ENV not set; defaulting to production"
        print_info "RAILS_ENV: $RAILS_ENV"
    else
        print_info "RAILS_ENV: $RAILS_ENV"
    fi

    if [[ "$RAILS_ENV" != "production" ]]; then
        print_warning "RAILS_ENV is '$RAILS_ENV', not 'production'. Verify this is intended."
    fi

    if ! rails runner "puts 'ok'" >/dev/null 2>&1; then
        print_error "Rails environment is not usable."
        print_error "Ensure you are in the Mastodon installation directory and"
        print_error "that the database is reachable with RAILS_ENV=$RAILS_ENV."
        exit 1
    fi

    # Version gate
    local detected=""
    detected=$(rails runner "print Mastodon::Version.to_s" 2>/dev/null || true)
    detected="${detected//[[:space:]]/}"

    if [[ -z "$detected" ]]; then
        print_warning "Could not determine Mastodon version; continuing without a version check"
    else
        print_info "Mastodon version: $detected (minimum supported: $MIN_MASTODON_VERSION)"
        if ! version_ge "$detected" "$MIN_MASTODON_VERSION"; then
            print_error "Mastodon $detected is older than the supported minimum $MIN_MASTODON_VERSION"
            print_error "This script uses flags that do not exist on older releases."
            exit 1
        fi
        if version_ge "$detected" "$TESTED_MASTODON_VERSION" && [[ "$detected" != "$TESTED_MASTODON_VERSION" ]]; then
            print_warning "Mastodon $detected is newer than the tested version $TESTED_MASTODON_VERSION; verify flags before automating."
        fi
    fi

    if ! command_exists stdbuf; then
        print_warning "stdbuf not found; output will be fully buffered"
    fi

    print_success "All prerequisites satisfied"
}

# =============================================================================
# Help
# =============================================================================

show_help() {
    cat << EOF
$SCRIPT_NAME v$SCRIPT_VERSION

Usage: $0 [OPTIONS] [OPERATION]

Cleanup and maintenance for a Mastodon instance (requires Mastodon >= $MIN_MASTODON_VERSION).

OPTIONS:
    --dry-run                Preview only. Commands with native --dry-run support
                             run with it; others are skipped with a notice.
    --yes                    Confirm destructive operations when non-interactive
    --include-subdomains     Include subdomains when purging domains (opt-in)
    --purge-domain-blocks    Also delete the DomainBlock rows while purging
    --no-keep-interacted     Do not protect media attached to statuses locals
                             favourited, bookmarked, quoted, replied to, or boosted
    --concurrency N          Concurrency level (default: $DEFAULT_CONCURRENCY)
    --media-days N           Media retention days (default: $DEFAULT_MEDIA_DAYS)
    --profile-media-days N   Profile media retention days (default: $DEFAULT_PROFILE_MEDIA_DAYS)
    --preview-cards-days N   Preview cards retention days (default: $DEFAULT_PREVIEW_CARDS_DAYS)
    --statuses-days N        Remote statuses retention days (default: $DEFAULT_STATUSES_DAYS)
    --inactive-days N        Inactive threshold, days (default: $DEFAULT_INACTIVE_DAYS)
    --domain-batch N         Domains per tootctl invocation (default: $DEFAULT_DOMAIN_BATCH)
    --verbose                Verbose output
    --log-file [PATH]        Log to file (default: cleanup_<timestamp>.log)
    --list-operations        List available operations
    --help                   Show this help message
    --version                Show version information

OPERATIONS:
    Basic:
        --domains              Export and purge blocked domains
        --accounts             Clean up accounts (cull + prune)
        --media                Remove old media files
        --profile-media        Remove old profile media
        --preview-cards        Remove old preview cards
        --remote-statuses      Remove old remote statuses
        --orphaned-media       Remove orphaned media
        --feeds                Build all feeds
        --clear-cache          Clear Redis cache
        --elasticsearch        Elasticsearch maintenance

    Combined:
        --all-media            All media operations
        --maintenance          Standard maintenance operations
        --full                 Complete cleanup (all operations)

    Enhanced:
        --account-cleanup      Enhanced account cleanup (inactive + cull + prune)
        --media-audit          Media audit (stats + orphans + cleanup)
        --domain-audit         Domain audit (list + check + purge)
        --system-health        System health check (info + stats + queue + cache)
        --deep-cleanup         Complete cleanup with cache clearing

DESTRUCTIVE OPERATIONS:
    The following permanently delete data and require --yes when stdin is not a
    TTY: --domains, --full, --deep-cleanup, --domain-audit, --account-cleanup,
    --clear-cache, --elasticsearch, --remote-statuses, --orphaned-media.

EXAMPLES:
    $0 --help
    $0 --dry-run --full
    $0 --domains
    $0 --dry-run --domains
    $0 --concurrency 8 --domains
    $0 --maintenance --yes --log-file
    $0 --media-days 60 --profile-media-days 60 --maintenance --yes

EOF
}

show_version() {
    echo "$SCRIPT_NAME v$SCRIPT_VERSION"
    echo "Author: $SCRIPT_AUTHOR"
    echo "Minimum Mastodon: $MIN_MASTODON_VERSION (tested: $TESTED_MASTODON_VERSION)"
}

list_operations() {
    print_header "Available Operations"
    echo
    echo -e "${CYAN}Basic Operations:${NC}"
    echo "  --domains              Export and purge blocked domains"
    echo "  --accounts             Clean up accounts (cull + prune)"
    echo "  --media                Remove old media files"
    echo "  --profile-media        Remove old profile media"
    echo "  --preview-cards        Remove old preview cards"
    echo "  --remote-statuses      Remove old remote statuses"
    echo "  --orphaned-media       Remove orphaned media"
    echo "  --feeds                Build all feeds"
    echo "  --clear-cache          Clear Redis cache"
    echo "  --elasticsearch        Elasticsearch maintenance"
    echo
    echo -e "${CYAN}Combined Operations:${NC}"
    echo "  --all-media            All media operations"
    echo "  --maintenance          Standard maintenance operations"
    echo "  --full                 Complete cleanup (all operations)"
    echo
    echo -e "${CYAN}Enhanced Operations:${NC}"
    echo "  --account-cleanup      Enhanced account cleanup"
    echo "  --media-audit          Media audit"
    echo "  --domain-audit         Domain audit"
    echo "  --system-health        System health check"
    echo "  --deep-cleanup         Complete cleanup with cache"
    echo
}

# =============================================================================
# Argument parsing
# =============================================================================

set_operation() {
    local operation="$1"

    if [[ -n "$SELECTED_OPERATION" ]]; then
        print_error "Only one operation can be selected at a time"
        print_error "Selected: --$SELECTED_OPERATION, requested: --$operation"
        return 1
    fi

    SELECTED_OPERATION="$operation"
    return 0
}

require_numeric() {
    local flag="$1" value="$2"
    if [[ -z "$value" ]] || ! is_numeric "$value"; then
        print_error "Invalid value for $flag: '$value'"
        return 1
    fi
    return 0
}

parse_arguments() {
    while (( $# > 0 )); do
        case "$1" in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --yes)
                ASSUME_YES=true
                shift
                ;;
            --include-subdomains)
                INCLUDE_SUBDOMAINS=true
                shift
                ;;
            --no-include-subdomains)
                INCLUDE_SUBDOMAINS=false
                shift
                ;;
            --purge-domain-blocks)
                PURGE_DOMAIN_BLOCKS=true
                shift
                ;;
            --keep-interacted)
                KEEP_INTERACTED=true
                shift
                ;;
            --no-keep-interacted)
                KEEP_INTERACTED=false
                shift
                ;;
            --concurrency)
                require_numeric "--concurrency" "${2:-}" || exit 1
                CONCURRENCY="$2"
                shift 2
                ;;
            --media-days)
                require_numeric "--media-days" "${2:-}" || exit 1
                MEDIA_DAYS="$2"
                shift 2
                ;;
            --profile-media-days)
                require_numeric "--profile-media-days" "${2:-}" || exit 1
                PROFILE_MEDIA_DAYS="$2"
                shift 2
                ;;
            --preview-cards-days)
                require_numeric "--preview-cards-days" "${2:-}" || exit 1
                PREVIEW_CARDS_DAYS="$2"
                shift 2
                ;;
            --statuses-days)
                require_numeric "--statuses-days" "${2:-}" || exit 1
                STATUSES_DAYS="$2"
                shift 2
                ;;
            --inactive-days)
                require_numeric "--inactive-days" "${2:-}" || exit 1
                INACTIVE_DAYS="$2"
                shift 2
                ;;
            --domain-batch)
                require_numeric "--domain-batch" "${2:-}" || exit 1
                DOMAIN_BATCH="$2"
                shift 2
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --log-file)
                LOG_TO_FILE=true
                if [[ -n "${2:-}" && "${2:-}" != --* ]]; then
                    LOG_FILE="$2"
                    shift 2
                else
                    LOG_FILE="cleanup_$(date +%Y%m%d_%H%M%S).log"
                    shift
                fi
                ;;
            --list-operations)
                list_operations
                exit 0
                ;;
            --help)
                show_help
                exit 0
                ;;
            --version)
                show_version
                exit 0
                ;;
            --domains|--accounts|--media|--profile-media|--preview-cards|\
            --remote-statuses|--orphaned-media|--feeds|--clear-cache|\
            --elasticsearch|--all-media|--maintenance|--full|\
            --account-cleanup|--media-audit|--domain-audit|--system-health|\
            --deep-cleanup)
                set_operation "${1#--}" || exit 1
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                print_error "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

# =============================================================================
# Individual operations
# =============================================================================
#
# All return 0 on success, 1 on failure. Callers aggregate with `|| rc=1`.

export_domain_blocks() {
    local description="Export domain blocks to $DOMAIN_BLOCKS_FILE"

    # Only remove the previous export once we are committed to rewriting it.
    # During a dry run DOMAIN_BLOCKS_FILE points at a temporary path, so the
    # operator's existing export is never touched.
    if [[ -f "$DOMAIN_BLOCKS_FILE" ]]; then
        print_info "Replacing existing $DOMAIN_BLOCKS_FILE"
        rm -f -- "$DOMAIN_BLOCKS_FILE"
    fi

    local count=0
    count=$(rails runner "
        domains = DomainBlock.order(:domain).pluck(:domain)
        File.open('$DOMAIN_BLOCKS_FILE', 'w') do |f|
            domains.each { |d| f.puts d }
        end
        print domains.size
    " 2>&1 </dev/null) || {
        print_error "Failed to export domain blocks"
        # Surface the Rails diagnostic; otherwise SQL/permission errors are lost.
        if [[ -n "$count" ]]; then
            printf '%s\n' "$count" >&2
        fi
        return 1
    }
    print_info "Exported $count domain(s)"

    if [[ ! -f "$DOMAIN_BLOCKS_FILE" ]]; then
        print_error "Domain blocks file was not created"
        return 1
    fi

    print_success "Exported domain blocks to $DOMAIN_BLOCKS_FILE"
    return 0
}

purge_domains() {
    print_header "Purging Blocked Domains"

    if [[ ! -f "$DOMAIN_BLOCKS_FILE" ]]; then
        print_error "Domain blocks file not found: $DOMAIN_BLOCKS_FILE"
        return 1
    fi

    if ! confirm_destructive "purge all blocked domains (accounts and statuses deleted)"; then
        return 1
    fi

    # Read the file and normalise entries into an array.
    local -a domains=()
    local line domain_name
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]]; then
            continue
        fi
        # Take the first CSV field, then strip surrounding whitespace.
        domain_name="${line%%,*}"
        domain_name="${domain_name#"${domain_name%%[![:space:]]*}"}"
        domain_name="${domain_name%"${domain_name##*[![:space:]]}"}"
        if [[ -n "$domain_name" ]]; then
            domains+=("$domain_name")
        fi
    done < "$DOMAIN_BLOCKS_FILE"

    local total=${#domains[@]}
    if (( total == 0 )); then
        print_warning "No domains found to process"
        return 0
    fi

    print_info "Configuration:"
    print_info "  Dry run:            $DRY_RUN"
    print_info "  Include subdomains: $INCLUDE_SUBDOMAINS"
    print_info "  Purge domain blocks: $PURGE_DOMAIN_BLOCKS"
    print_info "  Concurrency:        $CONCURRENCY"
    print_info "  Batch size:         $DOMAIN_BATCH"
    print_info "  Total domains:      $total"

    local processed=0 errors=0 offset=0
    local -a shared_flags=( --concurrency "$CONCURRENCY" )
    if [[ "$INCLUDE_SUBDOMAINS" == "true" ]]; then
        shared_flags+=( --include-subdomains )
    fi
    if [[ "$PURGE_DOMAIN_BLOCKS" == "true" ]]; then
        shared_flags+=( --purge-domain-blocks )
    fi

    while (( offset < total )); do
        local -a batch=( "${domains[@]:offset:DOMAIN_BATCH}" )
        local batch_desc="Purge domains ${processed}..$(( processed + ${#batch[@]} )) of $total"

        if run_native_dry_run "$batch_desc" "${STDBUF[@]}" tootctl domains purge "${batch[@]}" "${shared_flags[@]}"; then
            processed=$(( processed + ${#batch[@]} ))
        else
            # Batch failed: retry one at a time so the failing domains are
            # identifiable rather than losing the whole batch.
            print_warning "Batch failed; retrying individually to attribute errors"
            local d
            for d in "${batch[@]}"; do
                if run_native_dry_run "Purge domain: $d" "${STDBUF[@]}" tootctl domains purge "$d" "${shared_flags[@]}"; then
                    processed=$(( processed + 1 ))
                else
                    errors=$(( errors + 1 ))
                    processed=$(( processed + 1 ))
                fi
            done
        fi

        offset=$(( offset + DOMAIN_BATCH ))
    done

    print_success "Domain purge completed: $processed processed, $errors errors"

    if (( errors > 0 )); then
        print_error "$errors domain(s) failed to purge"
        return 1
    fi
    return 0
}

cull_accounts() {
    print_header "Culling Non-existent Accounts"
    if ! confirm_destructive "cull remote accounts that no longer exist"; then
        return 1
    fi
    run_native_dry_run "Cull non-existent accounts" \
        "${STDBUF[@]}" tootctl accounts cull
}

prune_accounts() {
    print_header "Pruning Non-interactive Accounts"
    if ! confirm_destructive "prune remote accounts that never interacted locally"; then
        return 1
    fi
    run_native_dry_run "Prune non-interactive accounts" \
        "${STDBUF[@]}" tootctl accounts prune
}

remove_old_media() {
    print_header "Removing Old Media Files"

    local -a flags=( --days "$MEDIA_DAYS" --concurrency "$CONCURRENCY" )
    if [[ "$KEEP_INTERACTED" == "true" ]]; then
        flags+=( --keep-interacted )
    fi

    if ! confirm_destructive "remove media older than $MEDIA_DAYS days"; then
        return 1
    fi

    run_native_dry_run "Remove media files older than $MEDIA_DAYS days" \
        "${STDBUF[@]}" tootctl media remove "${flags[@]}"
}

remove_old_profile_media() {
    print_header "Removing Old Profile Media"
    if ! confirm_destructive "remove profile media older than $PROFILE_MEDIA_DAYS days"; then
        return 1
    fi
    run_native_dry_run "Remove profile media older than $PROFILE_MEDIA_DAYS days" \
        "${STDBUF[@]}" tootctl media remove \
        --prune-profiles \
        --days "$PROFILE_MEDIA_DAYS" \
        --concurrency "$CONCURRENCY"
}

remove_old_preview_cards() {
    print_header "Removing Old Preview Cards"
    if ! confirm_destructive "remove preview card media older than $PREVIEW_CARDS_DAYS days"; then
        return 1
    fi
    run_native_dry_run "Remove preview cards older than $PREVIEW_CARDS_DAYS days" \
        "${STDBUF[@]}" tootctl preview_cards remove \
        --days "$PREVIEW_CARDS_DAYS" \
        --concurrency "$CONCURRENCY"
}

remove_old_remote_statuses() {
    print_header "Removing Old Remote Statuses"
    if ! confirm_destructive "remove remote statuses older than $STATUSES_DAYS days"; then
        return 1
    fi
    # statuses remove has no --dry-run, so this is print-and-skip.
    run_no_dry_run "Remove remote statuses older than $STATUSES_DAYS days" \
        "${STDBUF[@]}" tootctl statuses remove \
        --days "$STATUSES_DAYS"
}

remove_orphaned_media() {
    # First argument "preview" forces a dry run and skips the confirmation gate.
    # Used by --media-audit so the listing step cannot delete anything.
    local mode="${1:-confirm}"

    if [[ "$mode" == "preview" ]]; then
        print_header "Previewing Orphaned Media"
    else
        print_header "Removing Orphaned Media"
    fi

    # remove-orphans only implements :s3 and :filesystem; :fog and :azure fail
    # hard. Detect the driver first rather than breaking composite operations.
    local storage=""
    storage=$(rails runner "print Paperclip::Attachment.default_options[:storage]" 2>/dev/null </dev/null || true)
    storage="${storage//[[:space:]]/}"

    case "$storage" in
        s3)
            print_info "Storage driver: s3 (listing requests may incur provider charges)"
            ;;
        filesystem)
            print_info "Storage driver: filesystem"
            ;;
        fog|azure|"")
            print_warning "Storage driver '${storage:-unknown}' is not supported by tootctl media remove-orphans"
            print_warning "Skipping orphaned media removal"
            return 0
            ;;
        *)
            print_warning "Unrecognised storage driver '$storage'; skipping orphaned media removal"
            return 0
            ;;
    esac

    if [[ "$mode" == "preview" ]]; then
        # Force the preview regardless of the global dry-run setting.
        local prev_dry="$DRY_RUN"
        DRY_RUN=true
        run_native_dry_run "Preview orphaned media" \
            "${STDBUF[@]}" tootctl media remove-orphans
        local rc=$?
        DRY_RUN="$prev_dry"
        return $rc
    fi

    if ! confirm_destructive "delete orphaned media files"; then
        return 1
    fi

    run_native_dry_run "Remove orphaned media files" \
        "${STDBUF[@]}" tootctl media remove-orphans
}

build_feeds() {
    print_header "Building All Feeds"
    print_info "Regenerating home and list feeds for all active users"

    run_native_dry_run "Build all feeds" \
        "${STDBUF[@]}" tootctl feeds build \
        --all \
        --concurrency "$CONCURRENCY"
}

clear_cache() {
    print_header "Clearing Cache"
    if ! confirm_destructive "clear the Redis cache"; then
        return 1
    fi
    # cache clear has no --dry-run.
    run_no_dry_run "Clear cache" \
        "${STDBUF[@]}" tootctl cache clear
}

elasticsearch_maintenance() {
    print_header "Elasticsearch Maintenance"

    local es_enabled=""
    es_enabled=$(rails runner "print((ENV['ES_ENABLED'] == 'true') ? 'true' : 'false')" 2>/dev/null </dev/null || true)
    es_enabled="${es_enabled//[[:space:]]/}"

    if [[ "$es_enabled" != "true" ]]; then
        print_warning "ES_ENABLED is not 'true'; skipping Elasticsearch maintenance"
        return 0
    fi

    if ! confirm_destructive "run tootctl search deploy (may rebuild indices)"; then
        return 1
    fi

    # search deploy has no --dry-run. It also erases index data when the index
    # specification has changed, so it is never run implicitly by a dry run.
    run_no_dry_run "Elasticsearch maintenance (search deploy)" \
        "${STDBUF[@]}" tootctl search deploy
}

# --- Enhanced operation backends -------------------------------------------
# These replace subcommands that do not exist in Mastodon's CLI.

list_inactive_accounts() {
    print_header "Listing Inactive Accounts"
    print_info "Accounts with no sign-in within $INACTIVE_DAYS days"

    local output=""
    output=$(rails runner "
        cutoff = $INACTIVE_DAYS.days.ago
        # COALESCE: a never-signed-in account must still be older than the cutoff.
        # Without this, every account that has not yet logged in is eligible
        # regardless of when it registered.
        scope  = User.where('COALESCE(current_sign_in_at, created_at) < ?', cutoff)
        scope  = scope.where(disabled: false).includes(:account)
        count  = 0
        scope.find_each do |u|
            next if u.account.nil?
            puts format('%-30s %s', u.account.acct, u.current_sign_in_at || 'never')
            count += 1
        end
        warn \"Total inactive: #{count}\"
    " 2>&1 </dev/null) || {
        print_error "Failed to list inactive accounts"
        return 1
    }

    echo "$output"
    return 0
}

delete_inactive_accounts() {
    print_header "Deleting Inactive Accounts"
    print_warning "Permanently deletes local accounts with no sign-in within $INACTIVE_DAYS days"

    if ! confirm_destructive "delete local accounts inactive for $INACTIVE_DAYS days"; then
        return 1
    fi

    local dry="false"
    [[ "$DRY_RUN" == "true" ]] && dry="true"

    local output=""
    output=$(rails runner "
        cutoff = $INACTIVE_DAYS.days.ago
        dry    = ($dry)
        scope  = User.where('COALESCE(current_sign_in_at, created_at) < ?', cutoff)
        scope  = scope.where(disabled: false).includes(:account)
        count  = 0
        scope.find_each do |u|
            next if u.account.nil?
            puts \"#{dry ? '[DRY RUN] would delete' : 'Deleting'} #{u.account.acct}\"
            unless dry
              # reserve_username is left at its default (true) so the local
              # handle is not released for reuse; Mastodon's own accounts delete
              # command behaves the same way.
              DeleteAccountService.new.call(u.account, reserve_email: false)
            end
            count += 1
        end
        puts \"#{dry ? 'Would delete' : 'Deleted'} #{count} inactive account(s)\"
    " 2>&1 </dev/null) || {
        print_error "Failed to delete inactive accounts"
        echo "$output"
        return 1
    }

    echo "$output"
    return 0
}

media_stats() {
    print_header "Media Statistics"
    # `media stats` does not exist; `media usage` is the real command.
    run_no_dry_run "Media usage statistics" \
        "${STDBUF[@]}" tootctl media usage
}

list_orphaned_media() {
    # `media list-orphans` does not exist. remove-orphans --dry-run is the
    # supported preview, and it must reuse remove_orphaned_media so the storage
    # guard applies and nothing is deleted when the caller is not a dry run.
    remove_orphaned_media preview
}

list_domain_blocks() {
    print_header "Listing Domain Blocks"

    local output=""
    output=$(rails runner "
        rows = DomainBlock.order(:severity, :domain).pluck(:domain, :severity)
        puts format('%-40s %s', 'DOMAIN', 'SEVERITY')
        rows.each { |d, s| puts format('%-40s %s', d, s) }
        puts \"Total: #{rows.size}\"
    " 2>&1 </dev/null) || {
        print_error "Failed to list domain blocks"
        return 1
    }

    echo "$output"
    return 0
}

check_domain_health() {
    print_header "Checking Domain Health"
    print_info "Probing suspended domains for reachability"

    local output=""
    output=$(rails runner "
        require 'net/http'
        domains = DomainBlock.where(severity: :suspend).pluck(:domain)
        if domains.empty?
          puts 'No suspended domains to check'
          exit 0
        end
        ok = 0
        bad = 0
        domains.each do |d|
          begin
            uri = URI('https://' + d)
            res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 5) do |http|
              http.request(Net::HTTP::Head.new('/'))
            end
            puts format('%-40s %s', d, res.code)
            ok += 1
          rescue => e
            puts format('%-40s unreachable (%s)', d, e.class)
            bad += 1
          end
        end
        puts \"Reachable: #{ok}, unreachable: #{bad}\"
    " 2>&1 </dev/null) || {
        print_error "Failed to check domain health"
        return 1
    }

    echo "$output"
    return 0
}

# --- Health probes ----------------------------------------------------------

system_info() {
    print_header "System Information"
    run_no_dry_run "System information" \
        "${STDBUF[@]}" rails runner "begin
            puts 'Mastodon Instance Information:'
            puts 'Rails environment:   ' + Rails.env
            puts 'Database adapter:    ' + ActiveRecord::Base.connection.adapter_name
            puts 'Mastodon version:    ' + Mastodon::Version.to_s
            puts 'Ruby version:        ' + RUBY_VERSION
            puts 'Rails version:       ' + Rails.version
            pg = ActiveRecord::Base.connection.execute('SELECT version()').first['version'] rescue 'unknown'
            puts 'PostgreSQL version:  ' + pg.to_s.split(',').first.to_s
          rescue => e
            puts 'Error: ' + e.message
            exit 1
          end"
}

system_stats() {
    print_header "System Statistics"
    run_no_dry_run "Instance statistics" \
        "${STDBUF[@]}" rails runner "begin
            puts 'Instance Statistics:'
            puts 'Users:             ' + User.count.to_s
            puts 'Statuses:          ' + Status.count.to_s
            puts 'Media attachments: ' + MediaAttachment.count.to_s
            puts 'Domains:           ' + Account.distinct.count(:domain).to_s
            puts 'Local accounts:    ' + Account.local.count.to_s
            puts 'Remote accounts:   ' + Account.remote.count.to_s
          rescue => e
            puts 'Error: ' + e.message
            exit 1
          end"
}

queue_status() {
    print_header "Queue Status"
    # Sidekiq::ProcessSet lives in sidekiq/api, which is not loaded by a bare
    # `require 'sidekiq'`. Require it explicitly.
    run_no_dry_run "Queue status" \
        "${STDBUF[@]}" rails runner "begin
            require 'sidekiq/api'
            puts 'Queue Status:'
            puts 'Sidekiq processes: ' + Sidekiq::ProcessSet.new.size.to_s
            total = Sidekiq::Stats.new.enqueued rescue nil
            puts 'Enqueued jobs:     ' + total.to_s if total
          rescue LoadError
            puts 'Sidekiq API not available'
          rescue => e
            puts 'Error: ' + e.message
            exit 1
          end"
}

cache_status() {
    print_header "Cache Status"
    # Rails.cache.redis returns a ConnectionPool, which has no #ping; use #with.
    run_no_dry_run "Cache status" \
        "${STDBUF[@]}" rails runner "begin
            puts 'Cache Status:'
            pool = Rails.cache.redis
            if pool.respond_to?(:with)
              alive = pool.with { |c| c.ping == 'PONG' } rescue false
              keys  = pool.with { |c| c.dbsize } rescue 'unknown'
            else
              alive = (pool.ping == 'PONG') rescue false
              keys  = (pool.dbsize rescue 'unknown')
            end
            puts 'Redis connected: ' + (alive ? 'true' : 'false')
            puts 'Cache keys:      ' + keys.to_s
          rescue => e
            puts 'Error: ' + e.message
            exit 1
          end"
}

# =============================================================================
# Operation groups
# =============================================================================
# Each accumulates failure rather than short-circuiting, so one bad step does
# not silently cancel the rest — but the group still reports failure.

run_domains() {
    local rc=0
    export_domain_blocks || rc=1
    purge_domains || rc=1
    return $rc
}

run_accounts() {
    local rc=0
    cull_accounts || rc=1
    prune_accounts || rc=1
    return $rc
}

run_media()                { remove_old_media; }
run_profile_media()        { remove_old_profile_media; }
run_preview_cards()        { remove_old_preview_cards; }
run_remote_statuses()      { remove_old_remote_statuses; }
run_orphaned_media()       { remove_orphaned_media; }
run_feeds()                { build_feeds; }

run_all_media() {
    local rc=0
    remove_old_media || rc=1
    remove_old_profile_media || rc=1
    remove_old_preview_cards || rc=1
    remove_orphaned_media || rc=1
    return $rc
}

run_maintenance() {
    local rc=0
    cull_accounts || rc=1
    prune_accounts || rc=1
    remove_old_media || rc=1
    remove_old_profile_media || rc=1
    remove_old_preview_cards || rc=1
    remove_old_remote_statuses || rc=1
    remove_orphaned_media || rc=1
    elasticsearch_maintenance || rc=1
    build_feeds || rc=1
    return $rc
}

run_full() {
    local rc=0
    export_domain_blocks || rc=1
    purge_domains || rc=1
    cull_accounts || rc=1
    prune_accounts || rc=1
    remove_old_media || rc=1
    remove_old_profile_media || rc=1
    remove_old_preview_cards || rc=1
    remove_old_remote_statuses || rc=1
    remove_orphaned_media || rc=1
    elasticsearch_maintenance || rc=1
    build_feeds || rc=1
    clear_cache || rc=1
    return $rc
}

run_deep_cleanup() {
    # --full already includes cache clearing; kept as an alias for compatibility.
    run_full
}

run_account_cleanup() {
    local rc=0
    list_inactive_accounts || rc=1
    delete_inactive_accounts || rc=1
    cull_accounts || rc=1
    prune_accounts || rc=1
    return $rc
}

run_media_audit() {
    local rc=0
    media_stats || rc=1
    list_orphaned_media || rc=1
    remove_orphaned_media || rc=1
    remove_old_media || rc=1
    remove_old_profile_media || rc=1
    remove_old_preview_cards || rc=1
    return $rc
}

run_domain_audit() {
    local rc=0
    list_domain_blocks || rc=1
    check_domain_health || rc=1
    export_domain_blocks || rc=1
    purge_domains || rc=1
    return $rc
}

run_system_health() {
    local rc=0
    system_info || rc=1
    system_stats || rc=1
    queue_status || rc=1
    cache_status || rc=1
    return $rc
}

execute_selected_operation() {
    case "$SELECTED_OPERATION" in
        domains)          run_domains ;;
        accounts)         run_accounts ;;
        media)            run_media ;;
        profile-media)    run_profile_media ;;
        preview-cards)    run_preview_cards ;;
        remote-statuses)  run_remote_statuses ;;
        orphaned-media)   run_orphaned_media ;;
        feeds)            run_feeds ;;
        clear-cache)      clear_cache ;;
        elasticsearch)    elasticsearch_maintenance ;;
        all-media)        run_all_media ;;
        maintenance)      run_maintenance ;;
        full)             run_full ;;
        account-cleanup)  run_account_cleanup ;;
        media-audit)      run_media_audit ;;
        domain-audit)     run_domain_audit ;;
        system-health)    run_system_health ;;
        deep-cleanup)     run_deep_cleanup ;;
        *)
            print_error "Unknown operation: $SELECTED_OPERATION"
            return 1
            ;;
    esac
}

# =============================================================================
# Main
# =============================================================================

# Handle informational flags before any environment checks, so --help and
# --version work outside a Mastodon installation.
preflight_informational() {
    local arg
    for arg in "$@"; do
        case "$arg" in
            --help|-h)          show_help; exit 0 ;;
            --version|-V)       show_version; exit 0 ;;
            --list-operations)  list_operations; exit 0 ;;
        esac
    done
}

# Serialise runs so two overlapping cron jobs cannot purge concurrently.
# Pure bash: `set -C` (noclobber) makes the redirection an atomic O_EXCL create,
# so no external binary is spawned.
acquire_lock() {
    if [[ -n "${MM_LOCKED:-}" ]]; then
        return 0
    fi

    local had_noclobber=false
    [[ -o noclobber ]] && had_noclobber=true

    set -C
    if { : > "$LOCKFILE"; } 2>/dev/null; then
        [[ "$had_noclobber" == "true" ]] || set +C
        printf '%s\n' "$$" > "$LOCKFILE"
        export MM_LOCKED=1
        trap 'rm -f -- "$LOCKFILE"' EXIT
        return 0
    fi
    [[ "$had_noclobber" == "true" ]] || set +C

    local holder=""
    IFS= read -r holder < "$LOCKFILE" 2>/dev/null || true
    print_error "Another run is already in progress (lock: $LOCKFILE${holder:+, pid $holder})"
    exit 1
}

main() {
    preflight_informational "$@"

    # Parse first: logging, verbosity and the operation all come from arguments.
    parse_arguments "$@"

    # Acquire the run lock BEFORE touching the log file: a second invocation
    # would otherwise truncate the active run's diagnostics before flock rejects it.
    if [[ -n "$SELECTED_OPERATION" ]]; then
        acquire_lock "$@"
    fi

    if [[ "$LOG_TO_FILE" == "true" ]]; then
        echo "=== $SCRIPT_NAME v$SCRIPT_VERSION - $(date) ===" > "$LOG_FILE"
    fi

    print_header "Starting Mastodon Cleanup Process"
    print_info "Script version: $SCRIPT_VERSION"
    print_info "Started at: $(date)"

    validate_configuration || exit 1

    # During a dry run, export into a private temporary directory so the preview
    # works without touching the operator's existing export. mktemp -d gives a
    # 0700 directory, which avoids both a predictable path and a world-readable
    # blocklist under a permissive umask.
    if [[ "$DRY_RUN" == "true" ]]; then
        MM_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/mm-dryrun.XXXXXX")"
        DOMAIN_BLOCKS_FILE="$MM_TMPDIR/domain_blocks.txt"
        trap 'rm -rf -- "$MM_TMPDIR"' EXIT
    fi

    check_prerequisites

    print_header "Configuration Summary"
    print_info "Operation:             ${SELECTED_OPERATION:-<none>}"
    print_info "Dry run:               $DRY_RUN"
    print_info "Assume yes:            $ASSUME_YES"
    print_info "Include subdomains:    $INCLUDE_SUBDOMAINS"
    print_info "Purge domain blocks:   $PURGE_DOMAIN_BLOCKS"
    print_info "Keep interacted media: $KEEP_INTERACTED"
    print_info "Concurrency:           $CONCURRENCY"
    print_info "Media retention:       $MEDIA_DAYS days"
    print_info "Profile media:         $PROFILE_MEDIA_DAYS days"
    print_info "Preview cards:         $PREVIEW_CARDS_DAYS days"
    print_info "Remote statuses:       $STATUSES_DAYS days"
    print_info "Inactive threshold:    $INACTIVE_DAYS days"
    print_info "Log to file:           ${LOG_TO_FILE}${LOG_FILE:+ ($LOG_FILE)}"

    if [[ -z "$SELECTED_OPERATION" ]]; then
        # A bare --dry-run is an attempt to preview something; make it an error
        # rather than silently succeeding. A plain invocation with no flags is
        # still just a warning, since "what do I do?" is a reasonable question.
        if [[ "$DRY_RUN" == "true" ]]; then
            print_error "--dry-run requires an operation."
            print_error "Example: $0 --dry-run --full"
            exit 1
        fi
        print_warning "No operation selected. Use --help to see available operations."
        exit 0
    fi

    # No `if` wrapper here: wrapping the dispatcher in a condition suspends
    # errexit for the entire call tree and hides failures.
    local rc=0
    execute_selected_operation || rc=$?

    if (( rc == 0 )); then
        print_header "Cleanup Process Complete"
        print_info "Operation: $SELECTED_OPERATION"
        print_info "Completed at: $(date)"
        print_success "Cleanup completed successfully!"
        exit 0
    else
        print_header "Cleanup Process Incomplete"
        print_error "Operation '$SELECTED_OPERATION' did not complete successfully"
        print_error "Review the failures above before re-running."
        print_info "Completed at: $(date)"
        exit 1
    fi
}

main "$@"

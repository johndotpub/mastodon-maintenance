#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Mastodon Instance Cleanup Script
# =============================================================================
# This script performs comprehensive cleanup operations on a Mastodon instance
# including domain purging, account management, media cleanup, and feed rebuilding.
#
# Usage: ./clean.sh [OPTIONS] [OPERATIONS]
#
# Options:
#   --dry-run              Run in dry-run mode (only affects domain operations)
#   --include-subdomains   Include subdomains when purging domains
#   --concurrency N        Set concurrency level (default: 16)
#   --verbose              Enable verbose output
#   --log-file            Log operations to file
#   --help                 Show this help message
#   --version              Show version information
#
# Operations:
#   Basic Operations:
#     --domains              Export and purge blocked domains
#     --accounts             Clean up accounts (cull + prune)
#     --media                Remove old media files
#     --profile-media        Remove old profile media
#     --preview-cards        Remove old preview cards
#     --remote-statuses      Remove old remote statuses
#     --orphaned-media       Remove orphaned media
#     --feeds                Build all feeds
#   
#   Combined Operations:
#     --all-media            All media operations
#     --maintenance          Standard maintenance operations
#     --full                 Complete cleanup (all operations)
#   
#   Enhanced Operations:
#     --account-cleanup      Enhanced account cleanup (inactive + cull + prune)
#     --media-audit          Media audit (stats + orphaned + cleanup)
#     --domain-audit         Domain audit (list + check + purge)
#     --system-health        System health check (info + stats + cache)
#     --deep-cleanup         Complete cleanup with cache clearing
#
# Examples:
#   Basic Operations:
#     ./clean.sh --dry-run                    # Full cleanup in dry-run mode
#     ./clean.sh --domains                    # Only domain operations
#     ./clean.sh --media                      # Only remove old media
#     ./clean.sh --accounts --orphaned-media  # Account cleanup + orphaned media
#     ./clean.sh --concurrency 8 --domains    # Domain ops with custom concurrency
#   
#   Combined Operations:
#     ./clean.sh --maintenance                # Standard maintenance operations
#     ./clean.sh --all-media                  # All media cleanup operations
#     ./clean.sh --full                       # Complete cleanup (all operations)
#   
#   Enhanced Operations:
#     ./clean.sh --account-cleanup            # Enhanced account cleanup
#     ./clean.sh --media-audit                # Complete media audit
#     ./clean.sh --domain-audit               # Domain audit and cleanup
#     ./clean.sh --system-health              # System health check
#     ./clean.sh --deep-cleanup               # Complete cleanup with cache
# =============================================================================

# Script metadata
readonly SCRIPT_NAME="Mastodon Cleanup Script"
readonly SCRIPT_VERSION="1.0.2"
readonly SCRIPT_AUTHOR="@johndotpub@rewt.link" # Mastodon account

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Default configuration
readonly DEFAULT_CONCURRENCY=16
readonly DEFAULT_MEDIA_DAYS=90
readonly DEFAULT_PROFILE_MEDIA_DAYS=90
readonly DEFAULT_PREVIEW_CARDS_DAYS=30
readonly DEFAULT_STATUSES_DAYS=30
readonly DOMAIN_BLOCKS_FILE="domain_blocks.txt"

# =============================================================================
# Operation Group Functions
# =============================================================================

# Usage: run_domains
# Description: Executes domain-related operations (export and purge)
# Returns: 0 on success, 1 on failure
run_domains() {
    export_domain_blocks
    purge_domains
}

# Usage: run_accounts
# Description: Executes account cleanup operations (cull and prune)
# Returns: 0 on success, 1 on failure
run_accounts() {
    cull_accounts
    prune_accounts
}

# Usage: run_media
# Description: Executes media cleanup operations (remove old media)
# Returns: 0 on success, 1 on failure
run_media() {
    remove_old_media
}

# Usage: run_profile_media
# Description: Executes profile media cleanup operations
# Returns: 0 on success, 1 on failure
run_profile_media() {
    remove_old_profile_media
}

# Usage: run_preview_cards
# Description: Executes preview cards cleanup operations
# Returns: 0 on success, 1 on failure
run_preview_cards() {
    remove_old_preview_cards
}

# Usage: run_remote_statuses
# Description: Executes remote statuses cleanup operations
# Returns: 0 on success, 1 on failure
run_remote_statuses() {
    remove_old_remote_statuses
}

# Usage: run_orphaned_media
# Description: Executes orphaned media cleanup operations
# Returns: 0 on success, 1 on failure
run_orphaned_media() {
    remove_orphaned_media
}

# Usage: run_feeds
# Description: Executes feed building operations
# Returns: 0 on success, 1 on failure
run_feeds() {
    build_feeds
}

# Usage: run_all_media
# Description: Executes all media cleanup operations
# Returns: 0 on success, 1 on failure
run_all_media() {
    remove_old_media
    remove_old_profile_media
    remove_old_preview_cards
    remove_orphaned_media
}

# Usage: run_maintenance
# Description: Executes standard maintenance operations
# Returns: 0 on success, 1 on failure
run_maintenance() {
    cull_accounts
    prune_accounts
    remove_old_media
    remove_old_profile_media
    remove_old_preview_cards
    remove_old_remote_statuses
    remove_orphaned_media
    elasticsearch_maintenance
    build_feeds
}

# Usage: run_full
# Description: Executes complete cleanup operations (all operations)
# Returns: 0 on success, 1 on failure
run_full() {
    export_domain_blocks
    purge_domains
    cull_accounts
    prune_accounts
    remove_old_media
    remove_old_profile_media
    remove_old_preview_cards
    remove_old_remote_statuses
    remove_orphaned_media
    elasticsearch_maintenance
    build_feeds
}

# Usage: run_account_cleanup
# Description: Executes enhanced account cleanup operations
# Returns: 0 on success, 1 on failure
run_account_cleanup() {
    list_inactive_accounts
    delete_inactive_accounts
    cull_accounts
    prune_accounts
}

# Usage: run_media_audit
# Description: Executes complete media audit operations
# Returns: 0 on success, 1 on failure
run_media_audit() {
    media_stats
    list_orphaned_media
    remove_orphaned_media
    remove_old_media
    remove_old_profile_media
    remove_old_preview_cards
}

# Usage: run_domain_audit
# Description: Executes domain audit operations
# Returns: 0 on success, 1 on failure
run_domain_audit() {
    list_domain_blocks
    check_domain_health
    export_domain_blocks
    purge_domains
}

# Usage: run_system_health
# Description: Executes system health check operations
# Returns: 0 on success, 1 on failure
run_system_health() {
    if [[ "$VERBOSE" == "true" ]]; then
        system_info
        system_stats
        queue_status
        cache_status
    else
        # Quiet mode: gather all health info without interstitial logging
        safe_execute "System information" \
            stdbuf -oL rails runner "begin; puts 'Mastodon Instance Information:'; puts 'Rails environment: ' + Rails.env; puts 'Database: ' + ActiveRecord::Base.connection.adapter_name; puts 'Mastodon version: ' + Mastodon::Version.to_s; puts 'Ruby version: ' + RUBY_VERSION; puts 'Rails version: ' + Rails.version; puts 'PostgreSQL version: ' + (ActiveRecord::Base.connection.execute('SELECT version()').first['version'] rescue 'unknown'); rescue => e; puts 'Error: ' + e.message; exit 1; end"
        
        safe_execute "System statistics" \
            stdbuf -oL rails runner "begin; puts 'Instance Statistics:'; puts 'Users: ' + User.count.to_s; puts 'Statuses: ' + Status.count.to_s; puts 'Media attachments: ' + MediaAttachment.count.to_s; puts 'Domains: ' + Account.distinct.count(:domain).to_s; puts 'Local accounts: ' + Account.local.count.to_s; puts 'Remote accounts: ' + Account.remote.count.to_s; rescue => e; puts 'Error: ' + e.message; exit 1; end"
        
        safe_execute "Queue status" \
            stdbuf -oL rails runner "begin; puts 'Queue Status:'; puts 'Sidekiq processes: ' + Sidekiq::ProcessSet.new.size.to_s rescue puts 'Sidekiq not available'; rescue => e; puts 'Error: ' + e.message; exit 1; end"
        
        safe_execute "Cache status" \
            stdbuf -oL rails runner "begin; puts 'Cache Status:'; puts 'Redis connected: ' + (Rails.cache.redis.ping == 'PONG' ? 'true' : 'false') rescue puts 'Redis connected: false'; puts 'Cache keys: ' + (Rails.cache.redis.dbsize rescue 'unknown').to_s; rescue => e; puts 'Error: ' + e.message; exit 1; end"
    fi
}

# Usage: run_deep_cleanup
# Description: Executes complete cleanup with cache clearing
# Returns: 0 on success, 1 on failure
run_deep_cleanup() {
    export_domain_blocks
    purge_domains
    cull_accounts
    prune_accounts
    remove_old_media
    remove_old_profile_media
    remove_old_preview_cards
    remove_old_remote_statuses
    remove_orphaned_media
    build_feeds
    clear_cache
}

# Global variables
DRY_RUN=false
INCLUDE_SUBDOMAINS=true
CONCURRENCY=$DEFAULT_CONCURRENCY
MEDIA_DAYS=$DEFAULT_MEDIA_DAYS
PROFILE_MEDIA_DAYS=$DEFAULT_PROFILE_MEDIA_DAYS
PREVIEW_CARDS_DAYS=$DEFAULT_PREVIEW_CARDS_DAYS
STATUSES_DAYS=$DEFAULT_STATUSES_DAYS
VERBOSE=false
LOG_TO_FILE=false
LOG_FILE=""
SELECTED_OPERATION=""

# =============================================================================
# Utility Functions
# =============================================================================

# Usage: print_log level color message
# Description: Prints colored output with timestamp
# Parameters: level (INFO/SUCCESS/WARNING/ERROR), color (ANSI color code), message (text to display)
# Returns: None
print_log() {
    local level="$1"
    local color="$2"
    local message="$3"
    local timestamp
    
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${color}[${timestamp}] [${level}]${NC} $message"
    
    if [[ "$LOG_TO_FILE" == "true" ]]; then
        echo "[${timestamp}] [${level}] $message" >> "$LOG_FILE"
    fi
}

# Usage: print_info message
# Description: Prints info-level message in blue
# Parameters: message (text to display)
# Returns: None
print_info() { 
    print_log "INFO" "$BLUE" "$1"
}

# Usage: print_success message
# Description: Prints success-level message in green
# Parameters: message (text to display)
# Returns: None
print_success() { 
    print_log "SUCCESS" "$GREEN" "$1"
}

# Usage: print_warning message
# Description: Prints warning-level message in yellow
# Parameters: message (text to display)
# Returns: None
print_warning() { 
    print_log "WARNING" "$YELLOW" "$1"
}

# Usage: print_error message
# Description: Prints error-level message in red to stderr
# Parameters: message (text to display)
# Returns: None
print_error() { 
    print_log "ERROR" "$RED" "$1" >&2
}

# Usage: print_header title
# Description: Prints a formatted header with timestamp
# Parameters: title (header text to display)
# Returns: None
print_header() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo -e "${PURPLE}================================${NC}"
    echo -e "${PURPLE}[${timestamp}] $1${NC}"
    echo -e "${PURPLE}================================${NC}"
    
    if [[ "$LOG_TO_FILE" == "true" ]]; then
        echo "[${timestamp}] [HEADER] $1" >> "$LOG_FILE"
    fi
}

# Usage: command_exists command_name
# Description: Checks if a command exists in PATH
# Parameters: command_name (name of command to check)
# Returns: 0 if command exists, 1 if not found
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Usage: is_numeric value
# Description: Validates if a value is numeric
# Parameters: value (string to validate)
# Returns: 0 if numeric, 1 if not
is_numeric() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

# Usage: validate_configuration
# Description: Validates all configuration parameters
# Returns: 0 if valid, 1 if invalid
validate_configuration() {
    # Validate concurrency (1-32)
    if [[ "$CONCURRENCY" -lt 1 || "$CONCURRENCY" -gt 32 ]]; then
        print_error "Concurrency must be between 1 and 32 (current: $CONCURRENCY)"
        return 1
    fi
    
    # Validate retention days (1-365)
    for var in MEDIA_DAYS PROFILE_MEDIA_DAYS PREVIEW_CARDS_DAYS STATUSES_DAYS; do
        local value="${!var}"
        if [[ "$value" -lt 1 || "$value" -gt 365 ]]; then
            print_error "$var must be between 1 and 365 days (current: $value)"
            return 1
        fi
    done
    
    return 0
}

# Usage: set_operation operation_name
# Description: Sets the selected operation, validates only one operation is selected
# Parameters: operation_name (name of operation to set)
# Returns: 0 on success, 1 on failure
set_operation() {
    local operation="$1"
    
    if [[ -n "$SELECTED_OPERATION" ]]; then
        print_error "Only one operation can be selected at a time"
        return 1
    fi
    
    SELECTED_OPERATION="$operation"
    print_info "Selected operation: $operation"
}

# Usage: list_operations
# Description: Lists all available operations with descriptions
# Returns: None
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

# Usage: safe_execute description command [args...]
# Description: Executes a command with error handling and logging
# Parameters: description (human-readable description), command (command to execute), args (command arguments)
# Returns: 0 on success, 1 on failure
safe_execute() {
    local description="$1"
    shift
    
    print_info "Executing: $description"
    
    if [[ "$VERBOSE" == "true" ]]; then
        print_info "Command: $*"
        print_info "Working directory: $(pwd)"
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_warning "DRY RUN: Would execute: $*"
        return 0
    fi
    
    # Execute with real-time output
    local exit_code
    
    if "$@" 2>&1; then
        exit_code=0
        print_success "Completed: $description"
        return 0
    else
        exit_code=$?
        print_error "Failed: $description (exit code: $exit_code)"
        return 1
    fi
}

# Usage: check_prerequisites
# Description: Checks if all required commands and environment are available
# Returns: 0 if all prerequisites met, 1 if any missing
check_prerequisites() {
    print_header "Checking Prerequisites"
    
    local missing_commands=()
    
    # Check for required commands
    for cmd in rails tootctl; do
        if ! command_exists "$cmd"; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        print_error "Missing required commands: ${missing_commands[*]}"
        print_error "Please ensure Rails and tootctl are available in your PATH"
        print_error "Make sure you're running this script from your Mastodon installation directory"
        print_error "You may need to run: bundle exec rails runner"
        exit 1
    fi
    
    # Check if we're in a Rails environment
    if ! rails runner "puts 'Rails environment check passed'" >/dev/null 2>&1; then
        print_error "Rails environment not properly configured"
        print_error "Please ensure you're running this script from your Mastodon installation directory"
        print_error "Make sure Rails is available and the database is accessible"
        print_error "You may need to run: bundle exec rails runner"
        exit 1
    fi
    
    print_success "All prerequisites satisfied"
}

# Usage: parse_arguments [args...]
# Description: Parses command line arguments and sets global variables
# Parameters: args (command line arguments)
# Returns: 0 on success, 1 on failure
parse_arguments() {
    print_header "Parsing Arguments"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                print_info "Dry run mode enabled (only affects domain operations)"
                print_warning "Note: Dry-run mode only works with domain operations. Other operations will run normally."
                shift
                ;;
            --include-subdomains)
                INCLUDE_SUBDOMAINS=true
                print_info "Subdomain inclusion enabled"
                shift
                ;;
            --concurrency)
                if [[ -z "${2:-}" ]] || ! is_numeric "${2:-}"; then
                    print_error "Invalid concurrency value: ${2:-}"
                    exit 1
                fi
                CONCURRENCY="$2"
                print_info "Concurrency set to: $CONCURRENCY"
                shift 2
                ;;
            --verbose)
                VERBOSE=true
                print_info "Verbose mode enabled"
                shift
                ;;
            --media-days)
                if [[ -z "${2:-}" ]] || ! is_numeric "${2:-}"; then
                    print_error "Invalid media days value: ${2:-}"
                    exit 1
                fi
                MEDIA_DAYS="$2"
                print_info "Media retention set to: $MEDIA_DAYS days"
                shift 2
                ;;
            --profile-media-days)
                if [[ -z "${2:-}" ]] || ! is_numeric "${2:-}"; then
                    print_error "Invalid profile media days value: ${2:-}"
                    exit 1
                fi
                PROFILE_MEDIA_DAYS="$2"
                print_info "Profile media retention set to: $PROFILE_MEDIA_DAYS days"
                shift 2
                ;;
            --preview-cards-days)
                if [[ -z "${2:-}" ]] || ! is_numeric "${2:-}"; then
                    print_error "Invalid preview cards days value: ${2:-}"
                    exit 1
                fi
                PREVIEW_CARDS_DAYS="$2"
                print_info "Preview cards retention set to: $PREVIEW_CARDS_DAYS days"
                shift 2
                ;;
            --statuses-days)
                if [[ -z "${2:-}" ]] || ! is_numeric "${2:-}"; then
                    print_error "Invalid statuses days value: ${2:-}"
                    exit 1
                fi
                STATUSES_DAYS="$2"
                print_info "Remote statuses retention set to: $STATUSES_DAYS days"
                shift 2
                ;;
            --log-file)
                LOG_TO_FILE=true
                LOG_FILE="cleanup_$(date +%Y%m%d_%H%M%S).log"
                print_info "Logging to file: $LOG_FILE"
                shift
                ;;
            # Operation flags
            --domains|--accounts|--media|--profile-media|--preview-cards|--remote-statuses|--orphaned-media|--feeds|--clear-cache|--elasticsearch|--all-media|--maintenance|--full|--account-cleanup|--media-audit|--domain-audit|--system-health|--deep-cleanup)
                local operation="${1#--}"
                if ! set_operation "$operation"; then
                    exit 1
                fi
                shift
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
            *)
                print_error "Unknown option: $1"
                print_error "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    print_success "Arguments parsed successfully"
}

# Usage: show_help
# Description: Displays comprehensive help information
# Returns: None
show_help() {
    cat << EOF
$SCRIPT_NAME v$SCRIPT_VERSION

Usage: $0 [OPTIONS] [OPERATIONS]

This script performs comprehensive cleanup operations on a Mastodon instance.

OPTIONS:
    --dry-run              Run in dry-run mode (only affects domain operations)
    --include-subdomains   Include subdomains when purging domains
    --concurrency N        Set concurrency level (default: $DEFAULT_CONCURRENCY)
    --media-days N         Set media retention days (default: $DEFAULT_MEDIA_DAYS)
    --profile-media-days N Set profile media retention days (default: $DEFAULT_PROFILE_MEDIA_DAYS)
    --preview-cards-days N Set preview cards retention days (default: $DEFAULT_PREVIEW_CARDS_DAYS)
    --statuses-days N      Set remote statuses retention days (default: $DEFAULT_STATUSES_DAYS)
    --verbose              Enable verbose output
    --log-file            Log operations to file
    --help                Show this help message
    --version             Show version information

OPERATIONS:
    Basic Operations:
        --domains              Export and purge blocked domains
        --accounts             Clean up accounts (cull + prune)
        --media                Remove old media files (configurable, default: $DEFAULT_MEDIA_DAYS days)
        --profile-media        Remove old profile media (configurable, default: $DEFAULT_PROFILE_MEDIA_DAYS days)
        --preview-cards        Remove old preview cards (configurable, default: $DEFAULT_PREVIEW_CARDS_DAYS days)
        --remote-statuses      Remove old remote statuses (configurable, default: $DEFAULT_STATUSES_DAYS days)
        --orphaned-media       Remove orphaned media
        --feeds                Build all feeds
        --clear-cache          Clear Redis cache
        --elasticsearch        Elasticsearch maintenance
    
    Combined Operations:
        --all-media            All media operations
        --maintenance          Standard maintenance operations
        --full                 Complete cleanup (all operations)
    
    Enhanced Operations:
        --account-cleanup      Enhanced account cleanup (inactive + cull + prune)
        --media-audit          Media audit (stats + orphaned + cleanup)
        --domain-audit         Domain audit (list + check + purge)
        --system-health        System health check (info + stats + cache)
        --deep-cleanup         Complete cleanup with cache clearing

EXAMPLES:
    Basic Operations:
        $0 --dry-run                    # Full cleanup in dry-run mode
        $0 --domains                    # Only domain operations
        $0 --media                      # Only remove old media
        $0 --accounts --orphaned-media  # Account cleanup + orphaned media
        $0 --concurrency 8 --domains    # Domain ops with custom concurrency
    
    Combined Operations:
        $0 --maintenance                # Standard maintenance operations
        $0 --all-media                  # All media cleanup operations
        $0 --full                       # Complete cleanup (all operations)
    
    Enhanced Operations:
        $0 --account-cleanup            # Enhanced account cleanup
        $0 --media-audit                # Complete media audit
        $0 --domain-audit               # Domain audit and cleanup
        $0 --system-health              # System health check
        $0 --deep-cleanup               # Complete cleanup with cache
    
    Custom Retention Examples:
        $0 --media-days 60 --maintenance          # Custom media retention
        $0 --preview-cards-days 15 --maintenance  # Custom preview cards retention

EOF
}

# Usage: show_version
# Description: Displays script version information
# Returns: None
show_version() {
    echo "$SCRIPT_NAME v$SCRIPT_VERSION"
    echo "Author: $SCRIPT_AUTHOR"
}

# =============================================================================
# Main Functions
# =============================================================================

# Usage: export_domain_blocks
# Description: Exports domain blocks to a file for processing, sorted alphabetically
# Returns: 0 on success, 1 on failure
export_domain_blocks() {
    print_header "Exporting Domain Blocks"
    
    if [[ -f "$DOMAIN_BLOCKS_FILE" ]]; then
        print_info "Removing existing domain blocks file"
        rm -f "$DOMAIN_BLOCKS_FILE"
    fi
    
    print_info "Exporting domain blocks to $DOMAIN_BLOCKS_FILE (will be sorted alphabetically)"
    
    if ! rails runner "
        begin
            domains = DomainBlock.pluck(:domain).sort
            File.open('$DOMAIN_BLOCKS_FILE', 'w') do |f|
                domains.each { |d| f.puts d }
            end
            puts \"Exported \#{domains.count} domains to $DOMAIN_BLOCKS_FILE (sorted alphabetically)\"
        rescue => e
            puts \"Error exporting domains: \#{e.message}\"
            exit 1
        end
    " 2>/dev/null; then
        print_error "Failed to export domain blocks"
        return 1
    fi
    
    if [[ ! -f "$DOMAIN_BLOCKS_FILE" ]]; then
        print_error "Domain blocks file was not created"
        return 1
    fi
    
    local domain_count
    domain_count=$(wc -l < "$DOMAIN_BLOCKS_FILE" 2>/dev/null || echo "0")
    print_success "Exported $domain_count domains to $DOMAIN_BLOCKS_FILE (sorted alphabetically)"
}

# Usage: purge_domains
# Description: Purges domains from the domain blocks file with progress tracking
# Returns: 0 on success, 1 on failure
purge_domains() {
    print_header "Purging Blocked Domains"
    
    if [[ ! -f "$DOMAIN_BLOCKS_FILE" ]]; then
        print_error "Domain blocks file not found: $DOMAIN_BLOCKS_FILE"
        return 1
    fi
    
    local processed_count=0
    local error_count=0
    local total_domains=0
    
    # Count total domains first
    while IFS= read -r domain || [[ -n "$domain" ]]; do
        # Skip empty lines and comments
        if [[ -z "$domain" || "$domain" =~ ^[[:space:]]*# ]]; then
            continue
        fi
        
        # Extract domain name (handle CSV format)
        local domain_name
        domain_name=$(echo "$domain" | cut -d',' -f1 | xargs)
        
        if [[ -n "$domain_name" ]]; then
            ((total_domains++))
        fi
    done < "$DOMAIN_BLOCKS_FILE"
    
    print_info "Configuration:"
    print_info "  Dry run: $DRY_RUN"
    print_info "  Include subdomains: $INCLUDE_SUBDOMAINS"
    print_info "  Concurrency: $CONCURRENCY"
    print_info "  Total domains to process: $total_domains"
    
    if [[ $total_domains -eq 0 ]]; then
        print_warning "No domains found to process"
        return 0
    fi
    
    # Process domains with progress tracking
    while IFS= read -r domain || [[ -n "$domain" ]]; do
        # Skip empty lines and comments
        if [[ -z "$domain" || "$domain" =~ ^[[:space:]]*# ]]; then
            continue
        fi
        
        # Extract domain name (handle CSV format)
        local domain_name
        domain_name=$(echo "$domain" | cut -d',' -f1 | xargs)
        
        if [[ -z "$domain_name" ]]; then
            print_warning "Skipping empty domain entry"
            continue
        fi
        
        ((processed_count++))
        local progress_percent=$(( (processed_count * 100) / total_domains ))
        
        # Build tootctl command with conditional flags
        local cmd_args=(
            stdbuf -oL tootctl domains purge "$domain_name" 
            --concurrency "$CONCURRENCY"
        )
        
        if [[ "$DRY_RUN" == "true" ]]; then
            cmd_args+=(--dry-run)
        fi
        
        if [[ "$INCLUDE_SUBDOMAINS" == "true" ]]; then
            cmd_args+=(--include-subdomains)
        fi
        
        # Show progress before starting the command
        print_info "Processing domain: $domain_name ($processed_count/$total_domains - ${progress_percent}%)"
        
        if safe_execute "Purge domain: $domain_name" "${cmd_args[@]}"; then
            print_success "✓ Domain purged: $domain_name ($processed_count/$total_domains - ${progress_percent}%)"
        else
            ((error_count++))
            print_error "✗ Failed to purge: $domain_name ($processed_count/$total_domains - ${progress_percent}%)"
        fi
        
    done < "$DOMAIN_BLOCKS_FILE"
    
    print_success "Domain purge completed: $processed_count processed, $error_count errors (${progress_percent}% complete)"
}

# Usage: cull_accounts
# Description: Culls non-existent accounts
# Returns: 0 on success, 1 on failure
cull_accounts() {
    print_header "Culling Non-existent Accounts"
    
    safe_execute "Cull non-existent accounts" \
        stdbuf -oL tootctl accounts cull
}

# Usage: prune_accounts
# Description: Prunes non-interactive accounts
# Returns: 0 on success, 1 on failure
prune_accounts() {
    print_header "Pruning Non-interactive Accounts"
    
    safe_execute "Prune non-interactive accounts" \
        stdbuf -oL tootctl accounts prune
}

# Usage: remove_old_media
# Description: Removes old media files based on configured retention period
# Returns: 0 on success, 1 on failure
remove_old_media() {
    print_header "Removing Old Media Files"
    
    safe_execute "Remove media files older than $MEDIA_DAYS days" \
        stdbuf -oL tootctl media remove \
        --days "$MEDIA_DAYS" \
        --concurrency "$CONCURRENCY"
}

# Usage: remove_old_profile_media
# Description: Removes old profile media based on configured retention period
# Returns: 0 on success, 1 on failure
remove_old_profile_media() {
    print_header "Removing Old Profile Media"
    
    safe_execute "Remove profile media older than $PROFILE_MEDIA_DAYS days" \
        stdbuf -oL tootctl media remove \
        --prune-profiles \
        --days "$PROFILE_MEDIA_DAYS" \
        --concurrency "$CONCURRENCY"
}

# Usage: remove_old_preview_cards
# Description: Removes old preview cards based on configured retention period
# Returns: 0 on success, 1 on failure
remove_old_preview_cards() {
    print_header "Removing Old Preview Cards"
    
    safe_execute "Remove preview cards older than $PREVIEW_CARDS_DAYS days" \
        stdbuf -oL tootctl preview_cards remove \
        --days "$PREVIEW_CARDS_DAYS" \
        --concurrency "$CONCURRENCY"
}

# Usage: remove_old_remote_statuses
# Description: Removes old remote statuses based on configured retention period
# Returns: 0 on success, 1 on failure
remove_old_remote_statuses() {
    print_header "Removing Old Remote Statuses"
    
    safe_execute "Remove remote statuses older than $STATUSES_DAYS days" \
        stdbuf -oL tootctl statuses remove \
        --days "$STATUSES_DAYS"
}

# Usage: remove_orphaned_media
# Description: Removes orphaned media files
# Returns: 0 on success, 1 on failure
remove_orphaned_media() {
    print_header "Removing Orphaned Media"
    
    safe_execute "Remove orphaned media files" \
        stdbuf -oL tootctl media remove-orphans
}

# Usage: build_feeds
# Description: Builds all feeds for optimal performance
# Returns: 0 on success, 1 on failure
build_feeds() {
    print_header "Building All Feeds"
    
    print_info "This operation is expensive but useful for feed fixing"
    
    safe_execute "Build all feeds" \
        stdbuf -oL tootctl feeds build \
        --all \
        --concurrency "$CONCURRENCY"
}

# =============================================================================
# Enhanced Maintenance Functions
# =============================================================================

# Usage: list_inactive_accounts
# Description: Lists inactive accounts for review
# Returns: 0 on success, 1 on failure
list_inactive_accounts() {
    print_header "Listing Inactive Accounts"
    
    print_info "This will show accounts that haven't been active recently"
    
    safe_execute "List inactive accounts" \
        stdbuf -oL tootctl accounts list --inactive
}

# Usage: delete_inactive_accounts
# Description: Deletes inactive accounts permanently
# Returns: 0 on success, 1 on failure
delete_inactive_accounts() {
    print_header "Deleting Inactive Accounts"
    
    print_warning "This will permanently delete inactive accounts"
    
    safe_execute "Delete inactive accounts" \
        stdbuf -oL tootctl accounts delete --inactive
}

# Usage: media_stats
# Description: Shows media storage statistics
# Returns: 0 on success, 1 on failure
media_stats() {
    print_header "Media Statistics"
    
    print_info "Showing media storage statistics"
    
    safe_execute "Media statistics" \
        stdbuf -oL tootctl media stats
}

# Usage: list_orphaned_media
# Description: Lists orphaned media files before removal
# Returns: 0 on success, 1 on failure
list_orphaned_media() {
    print_header "Listing Orphaned Media"
    
    print_info "This will show orphaned media files before removal"
    
    safe_execute "List orphaned media" \
        stdbuf -oL tootctl media list-orphans
}

# Usage: list_domain_blocks
# Description: Lists current domain blocks
# Returns: 0 on success, 1 on failure
list_domain_blocks() {
    print_header "Listing Domain Blocks"
    
    print_info "Showing current domain blocks"
    
    safe_execute "List domain blocks" \
        stdbuf -oL tootctl domains list
}

# Usage: check_domain_health
# Description: Tests connectivity to blocked domains
# Returns: 0 on success, 1 on failure
check_domain_health() {
    print_header "Checking Domain Health"
    
    print_info "Testing connectivity to blocked domains"
    
    safe_execute "Check domain health" \
        stdbuf -oL tootctl domains check
}

# Usage: system_info
# Description: Shows system information and health status
# Returns: 0 on success, 1 on failure
system_info() {
    print_header "System Information"
    
    print_info "Showing system information and health"
    
    safe_execute "System information" \
        stdbuf -oL rails runner "begin; puts 'Mastodon Instance Information:'; puts 'Rails environment: ' + Rails.env; puts 'Database: ' + ActiveRecord::Base.connection.adapter_name; puts 'Mastodon version: ' + Mastodon::Version.to_s; puts 'Ruby version: ' + RUBY_VERSION; puts 'Rails version: ' + Rails.version; puts 'PostgreSQL version: ' + (ActiveRecord::Base.connection.execute('SELECT version()').first['version'] rescue 'unknown'); rescue => e; puts 'Error: ' + e.message; exit 1; end"
}

# Usage: system_stats
# Description: Shows instance statistics and usage information
# Returns: 0 on success, 1 on failure
system_stats() {
    print_header "System Statistics"
    
    print_info "Showing instance statistics and usage"
    
    safe_execute "System statistics" \
        stdbuf -oL rails runner "begin; puts 'Instance Statistics:'; puts 'Users: ' + User.count.to_s; puts 'Statuses: ' + Status.count.to_s; puts 'Media attachments: ' + MediaAttachment.count.to_s; puts 'Domains: ' + Account.distinct.count(:domain).to_s; puts 'Local accounts: ' + Account.local.count.to_s; puts 'Remote accounts: ' + Account.remote.count.to_s; rescue => e; puts 'Error: ' + e.message; exit 1; end"
}

# Usage: queue_status
# Description: Checks background job queue status
# Returns: 0 on success, 1 on failure
queue_status() {
    print_header "Queue Status"
    
    print_info "Checking background job queue status"
    
    safe_execute "Queue status" \
        stdbuf -oL rails runner "begin; puts 'Queue Status:'; puts 'Sidekiq processes: ' + Sidekiq::ProcessSet.new.size.to_s rescue puts 'Sidekiq not available'; rescue => e; puts 'Error: ' + e.message; exit 1; end"
}

# Usage: cache_status
# Description: Checks Redis cache status
# Returns: 0 on success, 1 on failure
cache_status() {
    print_header "Cache Status"
    
    print_info "Checking Redis cache status"
    
    safe_execute "Cache status" \
        stdbuf -oL rails runner "begin; puts 'Cache Status:'; puts 'Redis connected: ' + (Rails.cache.redis.ping == 'PONG' ? 'true' : 'false') rescue puts 'Redis connected: false'; puts 'Cache keys: ' + (Rails.cache.redis.dbsize rescue 'unknown').to_s; rescue => e; puts 'Error: ' + e.message; exit 1; end"
}

# Clear Redis cache
# Usage: clear_cache
# Description: Clears Redis cache using tootctl cache clear
# Returns: 0 on success, 1 on failure
clear_cache() {
    print_header "Clearing Cache"
    
    print_info "Clearing Redis cache (safe operation)"
    
    safe_execute "Clear cache" \
        stdbuf -oL tootctl cache clear
}

# Elasticsearch maintenance
# Usage: elasticsearch_maintenance
# Description: Performs Elasticsearch maintenance using tootctl search deploy
# Returns: 0 on success, 1 on failure
elasticsearch_maintenance() {
    print_header "Elasticsearch Maintenance"
    
    print_info "Performing Elasticsearch maintenance operations"
    
    safe_execute "Elasticsearch maintenance" \
        stdbuf -oL tootctl search deploy
}

# Usage: execute_selected_operation
# Description: Executes the selected operation based on SELECTED_OPERATION variable
# Returns: 0 on success, 1 on failure
execute_selected_operation() {
    case "$SELECTED_OPERATION" in
        domains) 
            run_domains 
            ;;
        accounts) 
            run_accounts 
            ;;
        media) 
            run_media 
            ;;
        profile-media) 
            run_profile_media 
            ;;
        preview-cards) 
            run_preview_cards 
            ;;
        remote-statuses) 
            run_remote_statuses 
            ;;
        orphaned-media) 
            run_orphaned_media 
            ;;
        feeds) 
            run_feeds 
            ;;
        clear-cache) 
            clear_cache 
            ;;
        elasticsearch) 
            elasticsearch_maintenance 
            ;;
        all-media) 
            run_all_media 
            ;;
        maintenance) 
            run_maintenance 
            ;;
        full) 
            run_full 
            ;;
        account-cleanup) 
            run_account_cleanup 
            ;;
        media-audit) 
            run_media_audit 
            ;;
        domain-audit) 
            run_domain_audit 
            ;;
        system-health) 
            run_system_health 
            ;;
        deep-cleanup) 
            run_deep_cleanup 
            ;;
        *) 
            print_error "Unknown operation: $SELECTED_OPERATION" 
            return 1 
            ;;
    esac
}

# =============================================================================
# Main Execution
# =============================================================================

# Usage: main [args...]
# Description: Main entry point for the script
# Parameters: args (command line arguments)
# Returns: 0 on success, 1 on failure
main() {
    print_header "Starting Mastodon Cleanup Process"
    print_info "Script version: $SCRIPT_VERSION"
    print_info "Started at: $(date)"
    
    # Initialize logging if requested
    if [[ "$LOG_TO_FILE" == "true" ]]; then
        print_info "Logging to: $LOG_FILE"
        echo "=== Mastodon Cleanup Log - $(date) ===" > "$LOG_FILE"
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Validate configuration
    if ! validate_configuration; then
        exit 1
    fi
    
    # Display configuration
    print_header "Configuration Summary"
    print_info "Dry run mode: $DRY_RUN"
    print_info "Include subdomains: $INCLUDE_SUBDOMAINS"
    print_info "Concurrency: $CONCURRENCY"
    print_info "Media retention: $MEDIA_DAYS days"
    print_info "Profile media retention: $PROFILE_MEDIA_DAYS days"
    print_info "Preview cards retention: $PREVIEW_CARDS_DAYS days"
    print_info "Remote statuses retention: $STATUSES_DAYS days"
    print_info "Verbose mode: $VERBOSE"
    print_info "Log to file: $LOG_TO_FILE"
    
    if [[ -z "$SELECTED_OPERATION" ]]; then
        print_warning "No operation selected. Use --help to see available operations."
        exit 0
    fi
    
    print_info "Executing operation: $SELECTED_OPERATION"
    
    # Execute the selected operation
    if execute_selected_operation; then
        print_success "Operation '$SELECTED_OPERATION' completed successfully!"
    else
        print_error "Operation '$SELECTED_OPERATION' failed"
        exit 1
    fi
    
    # Final summary
    print_header "Cleanup Process Complete"
    print_info "Operation: $SELECTED_OPERATION"
    print_info "Completed at: $(date)"
    print_success "Cleanup completed successfully!"
    exit 0
}

# Execute main function with all arguments
main "$@"
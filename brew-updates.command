#!/bin/bash

# Enhanced Homebrew Update Assistant
# Version: 2.0
# Author: johxan

# Enable strict error handling
set -e
set -u
set -o pipefail

###################
# Configuration
###################
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BACKUP_DIR="${HOME}/.brew_backups"
readonly BACKUP_FILE="${BACKUP_DIR}/brew_backup_$(date +%Y%m%d_%H%M%S)"
readonly LOG_DIR="${HOME}/.brew_logs"
readonly LOG_FILE="${LOG_DIR}/brew_update_$(date +%Y%m%d_%H%M%S).log"
readonly MAX_RETRIES=3
readonly TIMEOUT=300
readonly MIN_DISK_SPACE_GB=1
readonly CONFIG_FILE="${HOME}/.brew_update_config"

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_GENERAL_ERROR=1
readonly EXIT_NETWORK_ERROR=2
readonly EXIT_DISK_SPACE_ERROR=3
readonly EXIT_HOMEBREW_ERROR=4

# Color codes for better output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script options (can be set via command line)
DRY_RUN=false
VERBOSE=false
AUTO_YES=false
SKIP_CASKS=false
SKIP_CLEANUP=false

# Configuration variables
BACKUP_RETENTION_DAYS=30
MAX_BACKUP_COUNT=5
LOG_RETENTION_DAYS=30
AUTO_UPGRADE=false
SKIP_CASKS_BY_DEFAULT=false
CLEANUP_BY_DEFAULT=true
LOG_LEVEL="INFO"
EXCLUDED_FORMULAE=""
EXCLUDED_CASKS=""
# Check environment variable first, then default to false
ENABLE_NOTIFICATIONS="${ENABLE_NOTIFICATIONS:-false}"

###################
# Error Handling
###################
cleanup_on_exit() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo -e "\n${RED}❌ Script failed with exit code: ${exit_code}${NC}" >&2
        echo -e "${YELLOW}💡 Check the log file: ${LOG_FILE}${NC}" >&2
    fi
    exit $exit_code
}

handle_error() {
    local line_number=$1
    local error_code=$2
    echo -e "\n${RED}❌ Error at line ${line_number}, code: ${error_code}${NC}" >&2
    echo -e "${BLUE}📝 Log: ${LOG_FILE}${NC}" >&2
    exit "${error_code:-$EXIT_GENERAL_ERROR}"
}

trap 'cleanup_on_exit' EXIT
trap 'handle_error ${LINENO} $?' ERR

###################
# Utility Functions
###################
print_header() {
    echo -e "\n${BLUE}🍺 Homebrew Update Assistant v2.0${NC}"
    echo -e "${BLUE}===========================================${NC}\n"
}

print_separator() {
    echo -e "\n${BLUE}----------------------------------------${NC}"
}

log_message() {
    local level=${2:-INFO}
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $1"
    
    # Ensure log directory exists before writing
    if [[ -n "${LOG_FILE:-}" ]]; then
        mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null
        echo "$message" | tee -a "$LOG_FILE" 2>/dev/null || echo "$message"
    else
        echo "$message"
    fi
}

log_verbose() {
    if [ "$VERBOSE" = true ]; then
        log_message "$1" "VERBOSE"
    fi
}

log_error() {
    echo -e "${RED}$1${NC}" >&2
    log_message "$1" "ERROR"
}

log_warning() {
    echo -e "${YELLOW}$1${NC}"
    log_message "$1" "WARNING"
}

log_success() {
    echo -e "${GREEN}$1${NC}"
    log_message "$1" "SUCCESS"
}

send_notification() {
    local title="$1"
    local message="$2"
    local sound="${3:-default}"

    # Only send notifications if ENABLE_NOTIFICATIONS is true
    if [[ "${ENABLE_NOTIFICATIONS:-false}" != "true" ]]; then
        log_verbose "Notifications disabled (ENABLE_NOTIFICATIONS=${ENABLE_NOTIFICATIONS:-false})"
        return 0
    fi

    log_verbose "Sending notification: $title - $message"

    # Try terminal-notifier first (supports click actions to open log folder)
    # Use full path to ensure it works in LaunchAgent environment
    if /opt/homebrew/bin/terminal-notifier -title "$title" -message "$message" -sound "$sound" \
        -execute "open '${LOG_DIR}'" 2>/dev/null; then
        log_verbose "Notification sent successfully via terminal-notifier (clickable)"
        return 0
    fi

    # Fallback to osascript (works but not clickable)
    if command -v osascript &> /dev/null; then
        if osascript -e "display notification \"$message\" with title \"$title\" sound name \"$sound\"" 2>/dev/null; then
            log_verbose "Notification sent successfully via osascript (non-clickable)"
            return 0
        else
            log_verbose "Notification via osascript failed"
        fi
    fi
}

validate_input() {
    local input="$1"
    local pattern="$2"
    local description="$3"
    
    if [[ ! "$input" =~ $pattern ]]; then
        log_error "❌ Invalid $description: $input"
        return 1
    fi
    return 0
}

load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        log_verbose "Loading configuration from $CONFIG_FILE"
        # Safely source config file with validation
        while IFS='=' read -r key value; do
            # Skip comments and empty lines
            [[ "$key" =~ ^[[:space:]]*# ]] && continue
            [[ -z "$key" ]] && continue
            
            # Validate and set configuration variables
            case "$key" in
                BACKUP_RETENTION_DAYS)
                    validate_input "$value" '^[0-9]+$' "backup retention days" && BACKUP_RETENTION_DAYS="$value"
                    ;;
                MAX_BACKUP_COUNT)
                    validate_input "$value" '^[0-9]+$' "max backup count" && MAX_BACKUP_COUNT="$value"
                    ;;
                LOG_RETENTION_DAYS)
                    validate_input "$value" '^[0-9]+$' "log retention days" && LOG_RETENTION_DAYS="$value"
                    ;;
                AUTO_UPGRADE|SKIP_CASKS_BY_DEFAULT|CLEANUP_BY_DEFAULT|ENABLE_NOTIFICATIONS)
                    validate_input "$value" '^(true|false)$' "boolean value" && declare -g "$key"="$value"
                    ;;
                LOG_LEVEL)
                    validate_input "$value" '^(DEBUG|INFO|WARNING|ERROR)$' "log level" && LOG_LEVEL="$value"
                    ;;
                EXCLUDED_FORMULAE|EXCLUDED_CASKS)
                    # Allow space-separated package names with hyphens, slashes, and other common characters
                    # Empty string is also valid
                    if [[ -z "$value" ]] || validate_input "$value" '^[a-zA-Z0-9@._/-]+( [a-zA-Z0-9@._/-]+)*$' "package list"; then
                        declare -g "$key"="$value"
                    fi
                    ;;
            esac
        done < "$CONFIG_FILE"
    fi
}

show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

OPTIONS:
    -d, --dry-run      Show what would be updated without making changes
    -v, --verbose      Enable verbose logging
    -y, --yes          Automatically answer yes to prompts
    -s, --skip-casks   Skip cask updates
    -c, --skip-cleanup Skip cleanup operations
    -h, --help         Show this help message

EXAMPLES:
    $(basename "$0")                    # Interactive update
    $(basename "$0") --dry-run          # Preview updates only
    $(basename "$0") --yes --verbose    # Automated update with verbose output
    $(basename "$0") --skip-casks       # Update formulae only

CONFIGURATION:
    Create ~/.brew_update_config to customize behavior
    See README.md for configuration options
EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -y|--yes)
                AUTO_YES=true
                shift
                ;;
            -s|--skip-casks)
                SKIP_CASKS=true
                shift
                ;;
            -c|--skip-cleanup)
                SKIP_CLEANUP=true
                shift
                ;;
            -h|--help)
                show_usage
                exit $EXIT_SUCCESS
                ;;
            --)
                shift
                break
                ;;
            -*)
                log_error "Unknown option: $1"
                show_usage >&2
                exit $EXIT_GENERAL_ERROR
                ;;
            *)
                log_error "Unexpected argument: $1"
                show_usage >&2
                exit $EXIT_GENERAL_ERROR
                ;;
        esac
    done

    # Validate environment variables
    if [[ -n "${BREW_UPDATE_TIMEOUT:-}" ]]; then
        validate_input "$BREW_UPDATE_TIMEOUT" '^[0-9]+$' "timeout value" || exit $EXIT_GENERAL_ERROR
        readonly TIMEOUT="$BREW_UPDATE_TIMEOUT"
    fi
    
    if [[ -n "${BREW_UPDATE_MAX_RETRIES:-}" ]]; then
        validate_input "$BREW_UPDATE_MAX_RETRIES" '^[0-9]+$' "max retries" || exit $EXIT_GENERAL_ERROR
        readonly MAX_RETRIES="$BREW_UPDATE_MAX_RETRIES"
    fi
}

###################
# Setup Functions
###################
setup_directories() {
    mkdir -p "$BACKUP_DIR" "$LOG_DIR"
    log_verbose "Created directories: $BACKUP_DIR, $LOG_DIR"

    # Clean up old logs (after directories exist)
    cleanup_old_logs
}

check_homebrew() {
    if ! command -v brew >/dev/null 2>&1; then
        log_error "❌ Homebrew not found. Please install Homebrew first."
        echo "Visit: https://brew.sh" >&2
        exit $EXIT_HOMEBREW_ERROR
    fi
    log_verbose "✓ Homebrew found: $(command -v brew)"
}

check_prerequisites() {
    local missing_tools=()
    
    # Check for GNU coreutils (optional but recommended)
    if ! command -v gtimeout >/dev/null 2>&1; then
        log_warning "💡 Consider installing GNU coreutils for enhanced functionality:"
        echo "   brew install coreutils"
    fi
    
    # Check for other useful tools
    command -v git >/dev/null 2>&1 || missing_tools+=("git")
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_warning "⚠️  Missing recommended tools: ${missing_tools[*]}"
    fi
}

###################
# System Checks
###################
check_network() {
    log_verbose "Checking network connectivity..."
    if ! ping -c 1 -W 5 github.com >/dev/null 2>&1; then
        log_warning "⚠️  Network connectivity issues detected"
        return $EXIT_NETWORK_ERROR
    fi
    log_verbose "✓ Network connectivity OK"
    return $EXIT_SUCCESS
}

get_disk_space() {
    local path="$1"
    local available_gb
    
    if command -v gdf >/dev/null 2>&1; then
        available_gb=$(gdf -BG "$path" 2>/dev/null | awk 'NR==2 {gsub("G",""); print $4}' || echo "unknown")
    else
        available_gb=$(df -g "$path" 2>/dev/null | awk 'NR==2 {print $4}' || echo "unknown")
    fi
    
    echo "$available_gb"
}

check_disk_space() {
    local brew_prefix
    brew_prefix=$(brew --prefix 2>/dev/null) || {
        log_error "Failed to get Homebrew prefix"
        return $EXIT_HOMEBREW_ERROR
    }
    
    local available_gb
    available_gb=$(get_disk_space "$brew_prefix")
    
    if [[ "$available_gb" == "unknown" ]]; then
        log_warning "⚠️  Could not determine available disk space"
        return $EXIT_SUCCESS
    fi
    
    log_verbose "Available disk space: ${available_gb}GB"
    
    if [[ "$available_gb" -lt "$MIN_DISK_SPACE_GB" ]]; then
        log_warning "⚠️  Low disk space: ${available_gb}GB (minimum: ${MIN_DISK_SPACE_GB}GB)"
        return $EXIT_DISK_SPACE_ERROR
    fi
    
    log_verbose "✓ Sufficient disk space available"
    return $EXIT_SUCCESS
}

###################
# Backup Functions
###################
create_backup() {
    log_message "📑 Creating Homebrew backup..."
    
    if brew bundle dump --file="$BACKUP_FILE" 2>/dev/null; then
        log_success "✓ Backup created: $BACKUP_FILE"
    else
        log_warning "⚠️  Failed to create backup, continuing anyway..."
    fi
    
    # Keep only last 5 backups
    cleanup_old_backups
}

cleanup_old_backups() {
    local backup_count
    backup_count=$(find "$BACKUP_DIR" -name "brew_backup_*" -type f 2>/dev/null | wc -l | tr -d ' ')

    if [[ "$backup_count" -gt "$MAX_BACKUP_COUNT" ]]; then
        log_verbose "Cleaning up old backups (keeping last $MAX_BACKUP_COUNT)..."
        # Safer approach: get files, sort by modification time, remove oldest
        find "$BACKUP_DIR" -name "brew_backup_*" -type f -print0 2>/dev/null | \
            xargs -0 ls -t 2>/dev/null | \
            tail -n +$((MAX_BACKUP_COUNT + 1)) | \
            xargs rm -f 2>/dev/null || log_warning "Failed to clean some old backups"
    fi
}

cleanup_old_logs() {
    log_verbose "Cleaning up logs older than $LOG_RETENTION_DAYS days..."

    # Find and remove log files older than LOG_RETENTION_DAYS
    local deleted_count=0

    # Find log files older than retention period
    while IFS= read -r -d '' logfile; do
        if rm -f "$logfile" 2>/dev/null; then
            ((deleted_count++))
            log_verbose "Deleted old log: $(basename "$logfile")"
        fi
    done < <(find "$LOG_DIR" -name "brew_update_*.log*" -type f -mtime +$LOG_RETENTION_DAYS -print0 2>/dev/null)

    if [[ $deleted_count -gt 0 ]]; then
        log_verbose "Cleaned up $deleted_count old log file(s)"
    else
        log_verbose "No old logs to clean up"
    fi
}

###################
# Core Functions
###################
run_with_timeout() {
    local -a cmd_array
    local description=${2:-"command"}
    
    # Parse command into array to avoid eval security issues
    read -ra cmd_array <<< "$1"
    
    log_verbose "Running: ${cmd_array[*]}"
    
    if command -v gtimeout >/dev/null 2>&1; then
        if ! gtimeout "$TIMEOUT" "${cmd_array[@]}"; then
            log_error "❌ Timeout: $description"
            return $EXIT_GENERAL_ERROR
        fi
    elif command -v timeout >/dev/null 2>&1; then
        if ! timeout "$TIMEOUT" "${cmd_array[@]}"; then
            log_error "❌ Timeout: $description"
            return $EXIT_GENERAL_ERROR
        fi
    else
        # Fallback without timeout - log warning
        log_warning "No timeout command available, running without timeout"
        if ! "${cmd_array[@]}"; then
            log_error "❌ Failed: $description"
            return $EXIT_GENERAL_ERROR
        fi
    fi
    
    return $EXIT_SUCCESS
}

run_with_retry() {
    local cmd="$1"
    local description="${2:-command}"
    local retry_count=0
    local exit_code
    
    while [[ $retry_count -lt $MAX_RETRIES ]]; do
        if run_with_timeout "$cmd" "$description"; then
            return $EXIT_SUCCESS
        fi
        
        exit_code=$?
        retry_count=$((retry_count + 1))
        
        if [[ $retry_count -lt $MAX_RETRIES ]]; then
            local wait_time=$((retry_count * 2))
            log_warning "⚠️  Retry $retry_count/$MAX_RETRIES for: $description (waiting ${wait_time}s)"
            sleep "$wait_time"
        fi
    done
    
    log_error "❌ Failed after $MAX_RETRIES attempts: $description"
    return "$exit_code"
}

confirm_action() {
    local prompt="$1"
    local response
    
    if [[ "$AUTO_YES" == true ]]; then
        log_verbose "Auto-confirming: $prompt"
        return $EXIT_SUCCESS
    fi
    
    # Use read with prompt for better security
    read -r -p "$prompt (y/N): " response
    case "$response" in
        [Yy]|[Yy][Ee][Ss])
            return $EXIT_SUCCESS
            ;;
        *)
            return $EXIT_GENERAL_ERROR
            ;;
    esac
}

###################
# Update Functions
###################
update_homebrew() {
    log_message "1️⃣  Updating Homebrew..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log_message "🔍 DRY RUN: Would update Homebrew"
        return $EXIT_SUCCESS
    fi
    
    if run_with_retry "brew update" "Homebrew update"; then
        log_success "✓ Homebrew updated successfully"
        return $EXIT_SUCCESS
    else
        log_error "❌ Failed to update Homebrew"
        return $EXIT_HOMEBREW_ERROR
    fi
}

check_outdated_packages() {
    log_message "2️⃣  Checking for outdated packages..."
    
    local outdated_formulae outdated_casks
    local has_updates=false
    
    # Check formulae with error handling
    if ! outdated_formulae=$(brew outdated --formula 2>/dev/null); then
        log_warning "Failed to check outdated formulae"
        outdated_formulae=""
    fi
    
    # Check casks if not skipped
    if [[ "$SKIP_CASKS" == false ]]; then
        if ! outdated_casks=$(brew outdated --cask 2>/dev/null); then
            log_warning "Failed to check outdated casks"
            outdated_casks=""
        fi
    fi
    
    # Filter excluded packages
    if [[ -n "$EXCLUDED_FORMULAE" && -n "$outdated_formulae" ]]; then
        local excluded_pattern
        excluded_pattern=$(echo "$EXCLUDED_FORMULAE" | tr ' ' '|')
        outdated_formulae=$(echo "$outdated_formulae" | grep -vE "^($excluded_pattern)")
    fi
    
    if [[ -n "$EXCLUDED_CASKS" && -n "$outdated_casks" ]]; then
        local excluded_pattern
        excluded_pattern=$(echo "$EXCLUDED_CASKS" | tr ' ' '|')
        outdated_casks=$(echo "$outdated_casks" | grep -vE "^($excluded_pattern)")
    fi
    
    # Display results
    if [[ -n "$outdated_formulae" ]]; then
        echo -e "\n📦 Outdated formulae:"
        echo "$outdated_formulae" | sed 's/^/  /'
        has_updates=true
    fi
    
    if [[ -n "$outdated_casks" && "$SKIP_CASKS" == false ]]; then
        echo -e "\n🎲 Outdated casks:"
        echo "$outdated_casks" | sed 's/^/  /'
        has_updates=true
    fi
    
    if [[ "$has_updates" == false ]]; then
        log_success "✨ All packages are up to date!"
        send_notification "Homebrew Update" "All packages are up to date!" "Blow"
        return 1  # Nothing to update (non-error condition)
    fi

    # Count total updates
    local formula_count=0
    local cask_count=0
    [[ -n "$outdated_formulae" ]] && formula_count=$(echo "$outdated_formulae" | wc -l | tr -d ' ')
    [[ -n "$outdated_casks" ]] && cask_count=$(echo "$outdated_casks" | wc -l | tr -d ' ')
    local total_updates=$((formula_count + cask_count))

    send_notification "Homebrew Update" "📦 $total_updates package(s) available for update" "Purr"

    return $EXIT_SUCCESS  # Has updates
}

show_upgrade_preview() {
    if [[ "$DRY_RUN" == true ]] || confirm_action "🔍 Show upgrade preview?"; then
        echo -e "\n🔍 Upgrade preview:"
        
        # Show formulae preview
        if ! brew upgrade --dry-run 2>/dev/null; then
            log_warning "Could not generate formulae upgrade preview"
        fi
        
        # Show casks preview if not skipped
        if [[ "$SKIP_CASKS" == false ]]; then
            if ! brew upgrade --cask --dry-run 2>/dev/null; then
                log_warning "Could not generate cask upgrade preview"
            fi
        fi
        
        print_separator
    fi
}

upgrade_packages() {
    if [[ "$DRY_RUN" == true ]]; then
        log_message "🔍 DRY RUN: Would upgrade packages"
        return $EXIT_SUCCESS
    fi
    
    if ! confirm_action "🚀 Proceed with upgrade?"; then
        log_message "⏭️  Skipping package upgrade"
        return $EXIT_SUCCESS
    fi
    
    log_message "3️⃣  Upgrading packages..."
    
    local formulae_result=0
    local cask_result=0
    
    # Upgrade formulae
    if run_with_retry "brew upgrade --formula" "formulae upgrade"; then
        log_success "✓ Formulae upgraded successfully"
    else
        formulae_result=$?
        log_warning "⚠️  Some formulae upgrades failed"
    fi
    
    # Upgrade casks
    if [[ "$SKIP_CASKS" == false ]]; then
        if run_with_retry "brew upgrade --cask" "cask upgrade"; then
            log_success "✓ Casks upgraded successfully"
        else
            cask_result=$?
            log_warning "⚠️  Some cask upgrades failed"
        fi
    fi
    
    # Return worst exit code
    if [[ $formulae_result -ne 0 ]]; then
        return $formulae_result
    elif [[ $cask_result -ne 0 ]]; then
        return $cask_result
    fi
    
    return $EXIT_SUCCESS
}

###################
# Maintenance Functions
###################
parse_doctor_output() {
    local doctor_file="$1"
    local has_warnings=false
    local has_errors=false
    
    if [[ ! -f "$doctor_file" ]]; then
        return 0
    fi
    
    # Check for common warning patterns
    if grep -q "Warning:" "$doctor_file" 2>/dev/null; then
        has_warnings=true
        echo -e "\n${YELLOW}📋 Homebrew Doctor Warnings:${NC}"

        # Extract and summarize key warnings with helpful context
        if grep -q "formulae have the same name as core formulae" "$doctor_file" 2>/dev/null; then
            echo "  • Formula naming conflicts detected"
            echo "    ${BLUE}ℹ️  Use full tap names (e.g., 'hashicorp/tap/terraform' instead of 'terraform')${NC}"
        fi

        if grep -q "outdated" "$doctor_file" 2>/dev/null; then
            echo "  • Some packages may be outdated"
            echo "    ${BLUE}ℹ️  This script should have updated them automatically${NC}"
        fi

        if grep -q "cask" "$doctor_file" 2>/dev/null; then
            echo "  • Cask-related warnings found"
            echo "    ${BLUE}ℹ️  Usually safe to ignore unless specific casks aren't working${NC}"
        fi

        if grep -q "link" "$doctor_file" 2>/dev/null; then
            echo "  • Linking issues detected"
            echo "    ${BLUE}ℹ️  Run 'brew link --overwrite <formula>' to fix if needed${NC}"
        fi

        if grep -q "just used to help.*maintainers" "$doctor_file" 2>/dev/null; then
            echo "  • ${GREEN}Note: Homebrew says these warnings are informational only${NC}"
            echo "    ${BLUE}ℹ️  Safe to ignore if everything works fine${NC}"
        fi
    fi
    
    # Check for actual errors (not just warnings)
    if grep -qE "(Error:|error:|failed)" "$doctor_file" 2>/dev/null; then
        if ! grep -q "just used to help" "$doctor_file" 2>/dev/null; then
            has_errors=true
            echo -e "\n${RED}❌ Homebrew Doctor Errors:${NC}"
            grep -E "(Error:|error:|failed)" "$doctor_file" 2>/dev/null | head -3 | sed 's/^/  • /' || true
        fi
    fi
    
    # Show summary
    if [[ "$has_errors" == true ]]; then
        return 1
    elif [[ "$has_warnings" == true ]]; then
        return 2
    else
        return 0
    fi
}

run_doctor() {
    log_message "🏥 Running Homebrew doctor..."

    # Use .doctor.log extension so it opens in console viewer
    local doctor_file="${LOG_FILE%.log}.doctor.log"
    local doctor_exit_code
    
    # Run brew doctor and capture exit code
    if brew doctor --verbose > "$doctor_file" 2>&1; then
        doctor_exit_code=0
    else
        doctor_exit_code=$?
    fi
    
    # Parse the output for meaningful information
    local parse_result
    parse_doctor_output "$doctor_file" || parse_result=$?
    parse_result=${parse_result:-0}
    
    case $parse_result in
        0)
            log_success "✓ Homebrew doctor: No issues found"
            ;;
        1)
            log_warning "⚠️  Homebrew doctor found errors that need attention"
            echo -e "  ${BLUE}Full report: ${doctor_file}${NC}"
            ;;
        2)
            log_message "ℹ️  Homebrew doctor found warnings (mostly informational)"
            echo -e "  ${BLUE}Note: These are typically safe to ignore unless you're experiencing issues${NC}"
            if [[ "$VERBOSE" == true ]]; then
                echo -e "  ${BLUE}Full report: ${doctor_file}${NC}"
            fi
            ;;
    esac

    # Always return success - doctor warnings/errors are informational only
    # The script should continue even if doctor finds issues
    return $EXIT_SUCCESS
}

cleanup_homebrew() {
    if [[ "$SKIP_CLEANUP" == true ]]; then
        log_message "⏭️  Skipping cleanup (--skip-cleanup)"
        return $EXIT_SUCCESS
    fi
    
    log_message "4️⃣  Cleaning up Homebrew..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log_message "🔍 DRY RUN: Would run cleanup"
        if ! brew cleanup --dry-run 2>/dev/null; then
            log_warning "Could not generate cleanup preview"
        fi
        return $EXIT_SUCCESS
    fi
    
    # Main cleanup
    if run_with_retry "brew cleanup --prune=all" "cleanup"; then
        log_success "✓ Cleanup completed"
    else
        log_warning "⚠️  Cleanup encountered issues"
    fi
    
    # Check for unused dependencies only once
    local autoremove_preview
    if autoremove_preview=$(brew autoremove --dry-run 2>/dev/null) && \
       echo "$autoremove_preview" | grep -q "Would remove"; then
        if confirm_action "🗑️  Remove unused dependencies?"; then
            if ! brew autoremove 2>/dev/null; then
                log_warning "⚠️  Autoremove failed"
            else
                log_success "✓ Unused dependencies removed"
            fi
        fi
    else
        log_verbose "No unused dependencies to remove"
    fi
}

###################
# Summary Functions
###################
show_system_info() {
    log_message "📊 System Information:"
    log_message "  Homebrew: $(brew --version | head -1)"
    
    if command -v sw_vers >/dev/null 2>&1; then
        log_message "  macOS: $(sw_vers -productVersion)"
    elif command -v lsb_release >/dev/null 2>&1; then
        log_message "  Linux: $(lsb_release -d | cut -f2)"
    else
        log_message "  OS: $(uname -s) $(uname -r)"
    fi
    
    local disk_info
    disk_info=$(df -h "$(brew --prefix)" | awk 'NR==2 {print $4 " available"}')
    log_message "  Disk space: $disk_info"
}

create_clickable_link() {
    local file_path="$1"
    local display_name="${2:-$(basename "$file_path")}"
    local is_directory="${3:-false}"
    
    # Check if we're in a terminal that supports clickable actions
    if [[ -n "${TERM_PROGRAM:-}" ]] && [[ -t 1 ]]; then
        case "${TERM_PROGRAM}" in
            "iTerm.app")
                # iTerm2 supports custom URL schemes and command execution
                if [[ "$is_directory" == "true" ]]; then
                    # For directories, use the file:// scheme which works better in iTerm2
                    echo -e "\033]8;;file://${file_path}\033\\${display_name}\033]8;;\033\\"
                else
                    # For files, create a command URL that opens the file
                    local encoded_path
                    encoded_path=$(printf '%s' "$file_path" | sed 's/ /%20/g')
                    echo -e "\033]8;;x-iterm2://run?command=open%20%22${encoded_path}%22\033\\${display_name}\033]8;;\033\\"
                fi
                ;;
            "vscode")
                # VS Code terminal supports vscode:// URLs
                echo -e "\033]8;;vscode://file${file_path}\033\\${display_name}\033]8;;\033\\"
                ;;
            "Apple_Terminal")
                # Terminal.app has limited hyperlink support, show path with instruction
                echo "${display_name} (⌘+double-click path: ${file_path})"
                ;;
            *)
                # For other terminals, show the path
                echo "${display_name} (${file_path})"
                ;;
        esac
    else
        # Non-interactive or unsupported terminal
        echo "${display_name} (${file_path})"
    fi
}

show_file_links() {
    echo -e "\n${BLUE}📁 Quick Access Files:${NC}"
    
    # Main log file
    echo -n "  📝 Main Log: "
    create_clickable_link "$LOG_FILE"
    
    # Doctor report if it exists
    local doctor_file="${LOG_FILE%.log}.doctor.log"
    if [[ -f "$doctor_file" ]]; then
        echo -n "  🏥 Doctor Report: "
        create_clickable_link "$doctor_file"
    fi
    
    # Backup file
    echo -n "  💾 Backup: "
    create_clickable_link "$BACKUP_FILE"
    
    # Log directory
    echo -n "  📂 All Logs: "
    create_clickable_link "$LOG_DIR" "Open Log Directory" "true"
    
    # Backup directory
    echo -n "  📦 All Backups: "
    create_clickable_link "$BACKUP_DIR" "Open Backup Directory" "true"
    
    # Add interactive commands for quick access
    echo -e "\n${YELLOW}💡 Quick Commands (copy & paste):${NC}"
    echo -e "  ${GREEN}open \"$LOG_FILE\"${NC}  # Open main log"
    if [[ -f "${LOG_FILE%.log}.doctor.log" ]]; then
        echo -e "  ${GREEN}open \"${LOG_FILE%.log}.doctor.log\"${NC}  # Open doctor report"
    fi
    echo -e "  ${GREEN}open \"$BACKUP_FILE\"${NC}  # Open backup file"
    echo -e "  ${GREEN}open \"$LOG_DIR\"${NC}  # Open log directory"
    echo -e "  ${GREEN}open \"$BACKUP_DIR\"${NC}  # Open backup directory"
    
    # Add real-time log viewing
    echo -e "\n${YELLOW}📊 Monitor Logs:${NC}"
    echo -e "  ${GREEN}tail -f \"$LOG_FILE\"${NC}  # Follow log in real-time"
    echo -e "  ${GREEN}less \"$LOG_FILE\"${NC}  # Browse log with search"
}

show_final_summary() {
    local end_time
    end_time=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Only clear screen if in interactive mode and not redirected
    if [[ "$AUTO_YES" == false && -t 1 ]]; then
        clear
    fi
    
    print_header
    echo -e "${GREEN}📋 Update Summary${NC} ($end_time)"
    print_separator
    
    echo "  ✓ System checks completed"
    echo "  ✓ Backup created: $(basename "$BACKUP_FILE")"
    echo "  ✓ Homebrew updated"
    echo "  ✓ Package updates processed"
    echo "  ✓ Health checks completed"
    [[ "$SKIP_CLEANUP" == false ]] && echo "  ✓ Cleanup performed"
    
    # Show clickable file links
    show_file_links
    
    print_separator
    echo -e "\n${GREEN}🎉 Homebrew Update Assistant completed successfully!${NC}"
    echo -e "${BLUE}✨ Your system is now up to date and optimized.${NC}"
    
    # Only prompt if interactive and output is to terminal
    if [[ "$AUTO_YES" == false && -t 0 && -t 1 ]]; then
        echo -e "\n${YELLOW}📱 Press any key to close this window...${NC}"
        read -n 1 -s -r
        echo -e "\n${GREEN}Thank you for using Homebrew Update Assistant! 🍺${NC}"
        sleep 1
    fi
}

###################
# Main Function
###################
main() {
    local exit_code=$EXIT_SUCCESS
    
    # Parse command line arguments first (needed for setup)
    parse_arguments "$@"
    
    print_header
    setup_directories
    
    # Load configuration after directories are created
    load_config

    # Send start notification
    send_notification "Homebrew Update" "Starting Homebrew update process..." "Submarine"

    # Pre-flight checks
    check_homebrew
    check_prerequisites
    show_system_info
    print_separator
    
    # System health checks with proper error handling
    local network_status disk_status
    network_status=0
    disk_status=0
    
    check_network || {
        network_status=$?
        log_warning "🌐 Continuing despite network issues..."
    }
    
    check_disk_space || {
        disk_status=$?
        if [[ $disk_status -eq $EXIT_DISK_SPACE_ERROR ]]; then
            # In CI environments or with --yes flag, warn but don't exit
            if [[ "$AUTO_YES" == true ]] || [[ -n "${CI:-}" ]] || [[ -n "${GITHUB_ACTIONS:-}" ]]; then
                log_warning "💾 Low disk space detected in automated environment, continuing..."
            else
                log_error "Insufficient disk space. Aborting to prevent system issues."
                exit $EXIT_DISK_SPACE_ERROR
            fi
        else
            log_warning "💾 Continuing despite disk space warnings..."
        fi
    }
    
    # Create backup
    create_backup
    print_separator
    
    # Update process
    if ! update_homebrew; then
        exit_code=$?
        log_error "Homebrew update failed"
        exit "$exit_code"
    fi
    
    # Check for updates and upgrade if available
    if check_outdated_packages; then
        show_upgrade_preview
        if ! upgrade_packages; then
            exit_code=$?
            log_warning "Some package upgrades failed (exit code: $exit_code)"
        fi
    else
        log_verbose "No package updates needed, skipping upgrade phase"
    fi
    
    print_separator
    
    # Maintenance
    run_doctor
    if ! cleanup_homebrew; then
        log_warning "Cleanup encountered issues but continuing..."
    fi
    
    # Summary
    show_final_summary

    # Send completion notification
    if [[ $exit_code -eq 0 ]]; then
        send_notification "Homebrew Update" "✅ Update completed successfully!" "Glass"
    else
        send_notification "Homebrew Update" "⚠️ Update completed with warnings (code: $exit_code)" "Basso"
    fi

    exit "$exit_code"
}

# Run main function with all arguments
main "$@"
#!/bin/bash

# Enhanced Homebrew Update Assistant
# Author: johxan
#
# NOTE: Must stay compatible with macOS /bin/bash 3.2 (the LaunchAgent runs it):
# no associative arrays, no mapfile, and guard empty array expansions under set -u.

# Enable strict error handling
set -e
set -u
set -o pipefail

###################
# Configuration
###################
readonly SCRIPT_VERSION="2.2.1"
# Version of the <run>.summary.json format consumed by the UI (see docs/run-summary-schema.md)
readonly SUMMARY_SCHEMA_VERSION=1

readonly BACKUP_DIR="${HOME}/.brew_backups"
readonly LOG_DIR="${HOME}/.brew_logs"
readonly LOCK_DIR="${LOG_DIR}/.brew-updates.lock"
readonly LAUNCHAGENT_LABEL="com.user.brew-update"

# One timestamp per run so every file it produces shares the same run ID
# Declare and assign separately to avoid masking return values (SC2155)
RUN_ID="$(date +%Y%m%d_%H%M%S)"
readonly RUN_ID
RUN_START_EPOCH="$(date +%s)"
readonly RUN_START_EPOCH

readonly BACKUP_FILE="${BACKUP_DIR}/brew_backup_${RUN_ID}"
readonly LOG_FILE="${LOG_DIR}/brew_update_${RUN_ID}.log"
readonly SUMMARY_FILE="${LOG_DIR}/brew_update_${RUN_ID}.summary.json"
# Overridable via BREW_UPDATE_MAX_RETRIES / BREW_UPDATE_TIMEOUT (made readonly after parsing)
MAX_RETRIES=3
TIMEOUT=300
readonly MIN_DISK_SPACE_GB=1
readonly CONFIG_FILE="${HOME}/.brew_update_config"

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_GENERAL_ERROR=1
readonly EXIT_NETWORK_ERROR=2
readonly EXIT_DISK_SPACE_ERROR=3
readonly EXIT_HOMEBREW_ERROR=4
readonly EXIT_ALREADY_RUNNING=5

# Color codes for better output (cleared by --no-color or the NO_COLOR env var)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script options (can be set via command line)
DRY_RUN=false
VERBOSE=false
AUTO_YES=false
SKIP_CASKS=false
SKIP_CLEANUP=false
SKIP_SECURITY_SCAN=false
# Space-separated package names from --packages (empty = all outdated packages)
REQUESTED_PACKAGES=""

# Configuration variables (can be set via config file)
MAX_BACKUP_COUNT=5
LOG_RETENTION_DAYS=30
SKIP_CASKS_BY_DEFAULT=false
CLEANUP_BY_DEFAULT=true
EXCLUDED_FORMULAE=""
EXCLUDED_CASKS=""
# Check environment variable first, then default to false
ENABLE_NOTIFICATIONS="${ENABLE_NOTIFICATIONS:-false}"
SECURITY_SCAN_ENABLED=false
SECURITY_SCAN_SEVERITY="HIGH,CRITICAL"

# Run state recorded in the summary file. Package lists are space-separated names;
# *_DETAILS are newline-separated "name|installed|available" records.
LOCK_HELD=false
RUN_COMPLETED=false
RUN_TRIGGER=""
HOMEBREW_VERSION=""
OUTDATED_FORMULAE=""
OUTDATED_CASKS=""
OUTDATED_DETAILS=""
UPGRADED_FORMULAE=""
UPGRADED_CASKS=""
FAILED_FORMULAE=""
FAILED_CASKS=""
SKIPPED_EXCLUDED=""
SKIPPED_PINNED=""
SKIPPED_NOT_OUTDATED=""
BACKUP_CREATED=false
DOCTOR_STATUS="not_run"
SECURITY_STATUS="not_run"
SECURITY_VULN_COUNT=0
CLEANUP_STATUS="not_run"

if [[ -n "${NO_COLOR:-}" ]]; then
    RED='' GREEN='' YELLOW='' BLUE='' NC=''
fi

###################
# Error Handling
###################
cleanup_on_exit() {
    local exit_code=$?

    if [[ "$LOCK_HELD" == true ]]; then
        write_run_summary "$exit_code" || true
        rm -rf "$LOCK_DIR" 2>/dev/null || true
    fi

    if [[ $exit_code -ne 0 && $exit_code -ne $EXIT_ALREADY_RUNNING ]]; then
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
# Convert signals into normal exits so the EXIT trap writes the summary and releases the lock
trap 'exit 130' INT
trap 'exit 143' TERM

###################
# Utility Functions
###################
print_header() {
    echo -e "\n${BLUE}🍺 Homebrew Update Assistant v${SCRIPT_VERSION}${NC}"
    echo -e "${BLUE}===========================================${NC}\n"
}

print_separator() {
    echo -e "\n${BLUE}----------------------------------------${NC}"
}

log_message() {
    local level=${2:-INFO}
    # Declare and assign separately to avoid masking return values (SC2155)
    local message
    message="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $1"

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

trim_whitespace() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

# Normalize a raw config value: drop an inline " # comment", trim, and strip matching quotes
normalize_config_value() {
    local value="$1"
    local comment_pattern='^(.*[^[:space:]])?[[:space:]]+#'
    if [[ "$value" =~ $comment_pattern ]]; then
        value="${BASH_REMATCH[1]:-}"
    fi
    value="$(trim_whitespace "$value")"
    if [[ ${#value} -ge 2 ]]; then
        local first="${value:0:1}" last="${value: -1}"
        if [[ ( "$first" == '"' && "$last" == '"' ) || ( "$first" == "'" && "$last" == "'" ) ]]; then
            value="${value:1:${#value}-2}"
        fi
    fi
    printf '%s' "$value"
}

load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        log_verbose "Loading configuration from $CONFIG_FILE"
        # Safely parse config file with validation (never sourced)
        while IFS='=' read -r key value || [[ -n "$key" ]]; do
            # Skip comments and empty lines
            [[ "$key" =~ ^[[:space:]]*# ]] && continue
            key="$(trim_whitespace "$key")"
            [[ -z "$key" ]] && continue
            value="$(normalize_config_value "${value:-}")"

            # Validate and set configuration variables
            case "$key" in
                MAX_BACKUP_COUNT)
                    validate_input "$value" '^[0-9]+$' "max backup count" && MAX_BACKUP_COUNT="$value"
                    ;;
                LOG_RETENTION_DAYS)
                    validate_input "$value" '^[0-9]+$' "log retention days" && LOG_RETENTION_DAYS="$value"
                    ;;
                SKIP_CASKS_BY_DEFAULT)
                    validate_input "$value" '^(true|false)$' "boolean value" && SKIP_CASKS_BY_DEFAULT="$value"
                    ;;
                CLEANUP_BY_DEFAULT)
                    validate_input "$value" '^(true|false)$' "boolean value" && CLEANUP_BY_DEFAULT="$value"
                    ;;
                ENABLE_NOTIFICATIONS)
                    validate_input "$value" '^(true|false)$' "boolean value" && ENABLE_NOTIFICATIONS="$value"
                    ;;
                SECURITY_SCAN_ENABLED)
                    validate_input "$value" '^(true|false)$' "boolean value" && SECURITY_SCAN_ENABLED="$value"
                    ;;
                SECURITY_SCAN_SEVERITY)
                    # Allow comma-separated severity levels
                    validate_input "$value" '^(LOW|MEDIUM|HIGH|CRITICAL)(,(LOW|MEDIUM|HIGH|CRITICAL))*$' "security scan severity" && SECURITY_SCAN_SEVERITY="$value"
                    ;;
                EXCLUDED_FORMULAE)
                    # Allow space-separated package names with hyphens, slashes, and other common characters
                    # Empty string is also valid
                    if [[ -z "$value" ]] || validate_input "$value" '^[a-zA-Z0-9@._/-]+( [a-zA-Z0-9@._/-]+)*$' "package list"; then
                        EXCLUDED_FORMULAE="$value"
                    fi
                    ;;
                EXCLUDED_CASKS)
                    if [[ -z "$value" ]] || validate_input "$value" '^[a-zA-Z0-9@._/-]+( [a-zA-Z0-9@._/-]+)*$' "package list"; then
                        EXCLUDED_CASKS="$value"
                    fi
                    ;;
                AUTO_UPGRADE|LOG_LEVEL|BACKUP_RETENTION_DAYS)
                    log_verbose "Ignoring retired config key: $key"
                    ;;
            esac
        done < "$CONFIG_FILE"
    fi

    # Config defaults can only add skips; CLI flags still win when they skip
    [[ "$SKIP_CASKS_BY_DEFAULT" == true ]] && SKIP_CASKS=true
    [[ "$CLEANUP_BY_DEFAULT" == false ]] && SKIP_CLEANUP=true
    return 0
}

show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

OPTIONS:
    -d, --dry-run           Show what would be updated without making changes
    -v, --verbose           Enable verbose logging
    -y, --yes               Automatically answer yes to prompts
    -s, --skip-casks        Skip cask updates
    -c, --skip-cleanup      Skip cleanup operations
        --skip-security-scan Skip vulnerability scanning
    -p, --packages LIST     Only upgrade these packages (space- or comma-separated)
        --no-color          Disable colored output (also honors NO_COLOR)
        --version           Show version and exit
    -h, --help              Show this help message

EXAMPLES:
    $(basename "$0")                    # Interactive update
    $(basename "$0") --dry-run          # Preview updates only
    $(basename "$0") --yes --verbose    # Automated update with verbose output
    $(basename "$0") --skip-casks       # Update formulae only
    $(basename "$0") --packages "node git" --yes   # Upgrade selected packages

EXIT CODES:
    0 success, 1 general error, 2 network, 3 disk space, 4 Homebrew,
    5 another run is already in progress

CONFIGURATION:
    Create ~/.brew_update_config to customize behavior
    See README.md for configuration options
EOF
}

disable_colors() {
    RED='' GREEN='' YELLOW='' BLUE='' NC=''
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
            --skip-security-scan)
                SKIP_SECURITY_SCAN=true
                shift
                ;;
            -p|--packages)
                if [[ $# -lt 2 || -z "$2" ]]; then
                    log_error "--packages requires a package list"
                    exit $EXIT_GENERAL_ERROR
                fi
                local package_list
                package_list="$(trim_whitespace "${2//,/ }")"
                validate_input "$package_list" '^[a-zA-Z0-9@._+/-]+([[:space:]]+[a-zA-Z0-9@._+/-]+)*$' "package list" || exit $EXIT_GENERAL_ERROR
                # Collapse runs of whitespace to single spaces
                local -a package_names=()
                read -ra package_names <<< "$package_list"
                REQUESTED_PACKAGES="${package_names[*]}"
                shift 2
                ;;
            --no-color)
                disable_colors
                shift
                ;;
            --version)
                echo "brew-updates.command ${SCRIPT_VERSION}"
                exit $EXIT_SUCCESS
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
        TIMEOUT="$BREW_UPDATE_TIMEOUT"
    fi

    if [[ -n "${BREW_UPDATE_MAX_RETRIES:-}" ]]; then
        validate_input "$BREW_UPDATE_MAX_RETRIES" '^[0-9]+$' "max retries" || exit $EXIT_GENERAL_ERROR
        MAX_RETRIES="$BREW_UPDATE_MAX_RETRIES"
    fi
    readonly TIMEOUT MAX_RETRIES
}

###################
# Setup Functions
###################
setup_directories() {
    mkdir -p "$BACKUP_DIR" "$LOG_DIR"
    log_verbose "Created directories: $BACKUP_DIR, $LOG_DIR"
}

# Prevent overlapping runs (e.g. a manual run from the UI during the scheduled run).
# mkdir is atomic, so only one process can create the lock directory.
acquire_lock() {
    mkdir -p "$LOG_DIR"

    if ! mkdir "$LOCK_DIR" 2>/dev/null; then
        local holder_pid
        holder_pid="$(cat "$LOCK_DIR/pid" 2>/dev/null || true)"

        if [[ -n "$holder_pid" ]] && kill -0 "$holder_pid" 2>/dev/null; then
            echo "Another Homebrew update is already running (PID $holder_pid)" >&2
            return $EXIT_ALREADY_RUNNING
        fi

        # No PID yet may mean another run is between mkdir and writing its PID; only
        # treat a PID-less lock as stale once it is a few minutes old
        if [[ -z "$holder_pid" ]] && [[ -z "$(find "$LOCK_DIR" -maxdepth 0 -mmin +5 2>/dev/null)" ]]; then
            echo "Another Homebrew update is starting up" >&2
            return $EXIT_ALREADY_RUNNING
        fi

        echo "Removing stale lock from a previous run (PID ${holder_pid:-unknown})" >&2
        rm -rf "$LOCK_DIR"
        if ! mkdir "$LOCK_DIR" 2>/dev/null; then
            echo "Another Homebrew update is already running" >&2
            return $EXIT_ALREADY_RUNNING
        fi
    fi

    echo "$$" > "$LOCK_DIR/pid"
    LOCK_HELD=true
}

# scheduled = launched by our LaunchAgent; BREW_UPDATE_TRIGGER lets callers (e.g. the UI) label runs
detect_trigger() {
    if [[ -n "${BREW_UPDATE_TRIGGER:-}" ]]; then
        if validate_input "$BREW_UPDATE_TRIGGER" '^[a-z_]{1,32}$' "trigger name"; then
            RUN_TRIGGER="$BREW_UPDATE_TRIGGER"
            return 0
        fi
    fi

    if [[ "${XPC_SERVICE_NAME:-}" == "$LAUNCHAGENT_LABEL" ]]; then
        RUN_TRIGGER="scheduled"
    else
        RUN_TRIGGER="manual"
    fi
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
        BACKUP_CREATED=true
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
            deleted_count=$((deleted_count + 1))
            log_verbose "Deleted old log: $(basename "$logfile")"
        fi
    # Matches every per-run file (.log, .security.json, .summary.json, ...)
    done < <(find "$LOG_DIR" -maxdepth 1 -name "brew_update_*" -type f -mtime +"$LOG_RETENTION_DAYS" -print0 2>/dev/null)

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
            log_error "❌ Failed or timed out: $description"
            return $EXIT_GENERAL_ERROR
        fi
    elif command -v timeout >/dev/null 2>&1; then
        if ! timeout "$TIMEOUT" "${cmd_array[@]}"; then
            log_error "❌ Failed or timed out: $description"
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
    local exit_code=$EXIT_GENERAL_ERROR

    while [[ $retry_count -lt $MAX_RETRIES ]]; do
        # Capture the status with || - after `if cmd; then ... fi` $? is always 0
        exit_code=0
        run_with_timeout "$cmd" "$description" || exit_code=$?
        if [[ $exit_code -eq 0 ]]; then
            return $EXIT_SUCCESS
        fi

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

# True if a package name is in a space-separated list. Compares the short name so
# "hashicorp/tap/terraform" and "terraform" match each other.
package_in_list() {
    local name="${1##*/}"
    local entry
    for entry in $2; do
        [[ "${entry##*/}" == "$name" ]] && return 0
    done
    return 1
}

append_word() {
    if [[ -z "$1" ]]; then
        printf '%s' "$2"
    else
        printf '%s %s' "$1" "$2"
    fi
}

count_words() {
    local -a words=()
    read -ra words <<< "$1"
    echo "${#words[@]}"
}

# Print "name|installed|available|pinned" for each package in `brew outdated --verbose`
# output, ignoring any other lines (e.g. auto-update notices).
#   formula: "z3 (5.3.1) < 5.3.2"   pinned: "foo (1.0) < 1.2 [pinned at 1.0]"
#   cask:    "firefox (130.0) != 131.0"
parse_outdated_output() {
    local line pinned
    local pattern='^([^[:space:]]+) \(([^)]*)\) (<|!=) ([^[:space:]]+)'
    while IFS= read -r line; do
        if [[ "$line" =~ $pattern ]]; then
            pinned=false
            [[ "$line" == *"[pinned at"* ]] && pinned=true
            echo "${BASH_REMATCH[1]}|${BASH_REMATCH[2]}|${BASH_REMATCH[4]}|${pinned}"
        fi
    done <<< "$1"
}

# List outdated packages of a kind (formula|cask) as parsed records; fails if brew fails
list_outdated() {
    local kind="$1"
    local output
    output=$(brew outdated "--${kind}" --verbose 2>/dev/null) || return 1
    parse_outdated_output "$output"
}

# Apply exclusions, pins and --packages to one kind and record what will be upgraded
select_outdated() {
    local kind="$1" records="$2" excluded="$3"
    local selected="" name installed available pinned

    while IFS='|' read -r name installed available pinned; do
        [[ -z "$name" ]] && continue
        if [[ -n "$REQUESTED_PACKAGES" ]] && ! package_in_list "$name" "$REQUESTED_PACKAGES"; then
            continue
        fi
        if package_in_list "$name" "$excluded"; then
            SKIPPED_EXCLUDED="$(append_word "$SKIPPED_EXCLUDED" "$name")"
            continue
        fi
        if [[ "$pinned" == true ]]; then
            SKIPPED_PINNED="$(append_word "$SKIPPED_PINNED" "$name")"
            continue
        fi
        selected="$(append_word "$selected" "$name")"
        OUTDATED_DETAILS+="${name}|${installed}|${available}"$'\n'
    done <<< "$records"

    if [[ "$kind" == formula ]]; then
        OUTDATED_FORMULAE="$selected"
    else
        OUTDATED_CASKS="$selected"
    fi
}

# Log the selected packages of one kind with their versions
log_outdated_list() {
    local heading="$1" names="$2"
    local name record installed available

    log_message "$heading"
    for name in $names; do
        record="$(awk -F'|' -v n="$name" '$1 == n { print; exit }' <<< "$OUTDATED_DETAILS")"
        IFS='|' read -r _ installed available <<< "$record"
        log_message "  - ${name} (${installed}) → ${available}"
    done
}

check_outdated_packages() {
    log_message "2️⃣  Checking for outdated packages..."

    local formula_records="" cask_records=""

    if ! formula_records=$(list_outdated formula); then
        log_warning "Failed to check outdated formulae"
        formula_records=""
    fi

    if [[ "$SKIP_CASKS" == false ]]; then
        if ! cask_records=$(list_outdated cask); then
            log_warning "Failed to check outdated casks"
            cask_records=""
        fi
    fi

    select_outdated formula "$formula_records" "$EXCLUDED_FORMULAE"
    select_outdated cask "$cask_records" "$EXCLUDED_CASKS"

    # Report requested packages that have nothing to upgrade
    local requested
    for requested in $REQUESTED_PACKAGES; do
        if ! package_in_list "$requested" "$OUTDATED_FORMULAE $OUTDATED_CASKS $SKIPPED_EXCLUDED $SKIPPED_PINNED"; then
            SKIPPED_NOT_OUTDATED="$(append_word "$SKIPPED_NOT_OUTDATED" "$requested")"
        fi
    done

    [[ -n "$OUTDATED_FORMULAE" ]] && log_outdated_list "📦 Outdated formulae:" "$OUTDATED_FORMULAE"
    [[ -n "$OUTDATED_CASKS" ]] && log_outdated_list "🎲 Outdated casks:" "$OUTDATED_CASKS"
    [[ -n "$SKIPPED_EXCLUDED" ]] && log_message "⏭️  Excluded by config: $SKIPPED_EXCLUDED"
    [[ -n "$SKIPPED_PINNED" ]] && log_message "📌 Pinned (not upgraded): $SKIPPED_PINNED"
    [[ -n "$SKIPPED_NOT_OUTDATED" ]] && log_message "ℹ️  Requested but not outdated or not installed: $SKIPPED_NOT_OUTDATED"

    if [[ -z "$OUTDATED_FORMULAE" && -z "$OUTDATED_CASKS" ]]; then
        log_success "✨ All packages are up to date!"
        send_notification "Homebrew Update" "All packages are up to date!" "Blow"
        return 1  # Nothing to update (non-error condition)
    fi

    local formula_count cask_count
    formula_count=$(count_words "$OUTDATED_FORMULAE")
    cask_count=$(count_words "$OUTDATED_CASKS")
    local total_updates=$((formula_count + cask_count))

    log_message "📊 Total packages to update: $total_updates (formulae: $formula_count, casks: $cask_count)"
    send_notification "Homebrew Update" "📦 $total_updates package(s) available for update" "Purr"

    return $EXIT_SUCCESS  # Has updates
}

show_upgrade_preview() {
    if [[ "$DRY_RUN" == true ]] || confirm_action "🔍 Show upgrade preview?"; then
        echo -e "\n🔍 Upgrade preview:"
        local -a names=()

        if [[ -n "$OUTDATED_FORMULAE" ]]; then
            read -ra names <<< "$OUTDATED_FORMULAE"
            if ! brew upgrade --formula --dry-run "${names[@]}" 2>/dev/null; then
                log_warning "Could not generate formulae upgrade preview"
            fi
        fi

        if [[ -n "$OUTDATED_CASKS" ]]; then
            read -ra names <<< "$OUTDATED_CASKS"
            if ! brew upgrade --cask --dry-run "${names[@]}" 2>/dev/null; then
                log_warning "Could not generate cask upgrade preview"
            fi
        fi

        print_separator
    fi
}

# After upgrading, anything still outdated failed. Sets UPGRADED_<KIND> and FAILED_<KIND>.
verify_upgrades() {
    local kind="$1" attempted="$2"
    local still_outdated="" records upgraded="" failed="" name

    if records=$(list_outdated "$kind"); then
        still_outdated="$(cut -d'|' -f1 <<< "$records" | tr '\n' ' ')"
    else
        log_warning "Could not re-check outdated ${kind}s; upgrade results may be incomplete"
    fi

    for name in $attempted; do
        if package_in_list "$name" "$still_outdated"; then
            failed="$(append_word "$failed" "$name")"
        else
            upgraded="$(append_word "$upgraded" "$name")"
        fi
    done

    if [[ "$kind" == formula ]]; then
        UPGRADED_FORMULAE="$upgraded"
        FAILED_FORMULAE="$failed"
    else
        UPGRADED_CASKS="$upgraded"
        FAILED_CASKS="$failed"
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
    local upgrade_log_file="${LOG_FILE%.log}.upgrades.log"
    local -a names=()

    # Upgrade only the selected formulae (explicit names so exclusions are honored) -
    # capture output to both display and log file
    if [[ -n "$OUTDATED_FORMULAE" ]]; then
        log_message "Starting formulae upgrade..."
        read -ra names <<< "$OUTDATED_FORMULAE"
        if brew upgrade --formula "${names[@]}" 2>&1 | tee -a "$upgrade_log_file"; then
            log_success "✓ Formulae upgraded successfully"
        else
            formulae_result=$?
            log_warning "⚠️  Some formulae upgrades failed"
        fi

        verify_upgrades formula "$OUTDATED_FORMULAE"
        [[ -n "$UPGRADED_FORMULAE" ]] && log_outdated_list "📦 Upgraded formulae:" "$UPGRADED_FORMULAE"
        [[ -n "$FAILED_FORMULAE" ]] && log_warning "⚠️  Formulae still outdated: $FAILED_FORMULAE"
    fi

    # Upgrade casks
    if [[ -n "$OUTDATED_CASKS" ]]; then
        log_message "Starting casks upgrade..."
        read -ra names <<< "$OUTDATED_CASKS"
        if brew upgrade --cask "${names[@]}" 2>&1 | tee -a "$upgrade_log_file"; then
            log_success "✓ Casks upgraded successfully"
        else
            cask_result=$?
            log_warning "⚠️  Some cask upgrades failed"
        fi

        verify_upgrades cask "$OUTDATED_CASKS"
        [[ -n "$UPGRADED_CASKS" ]] && log_outdated_list "🎲 Upgraded casks:" "$UPGRADED_CASKS"
        [[ -n "$FAILED_CASKS" ]] && log_warning "⚠️  Casks still outdated: $FAILED_CASKS"
    fi

    # Log the full upgrade details file location
    if [[ -f "$upgrade_log_file" ]]; then
        log_message "📋 Full upgrade details: $upgrade_log_file"
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
    # Run brew doctor (exit code intentionally ignored - warnings are informational)
    # shellcheck disable=SC2015  # Using short-circuit OR for intentional non-critical behavior
    brew doctor --verbose > "$doctor_file" 2>&1 && true || true

    # Parse the output for meaningful information
    local parse_result
    parse_doctor_output "$doctor_file" || parse_result=$?
    parse_result=${parse_result:-0}

    case $parse_result in
        0)
            DOCTOR_STATUS="ok"
            log_success "✓ Homebrew doctor: No issues found"
            ;;
        1)
            DOCTOR_STATUS="errors"
            log_warning "⚠️  Homebrew doctor found errors that need attention"
            echo -e "  ${BLUE}Full report: ${doctor_file}${NC}"
            ;;
        2)
            DOCTOR_STATUS="warnings"
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

run_security_scan() {
    if [[ "$SKIP_SECURITY_SCAN" == true ]]; then
        SECURITY_STATUS="skipped"
        log_message "⏭️  Skipping security scan (--skip-security-scan)"
        return $EXIT_SUCCESS
    fi

    if [[ "$SECURITY_SCAN_ENABLED" != true ]]; then
        SECURITY_STATUS="disabled"
        log_verbose "Security scanning disabled in configuration"
        return $EXIT_SUCCESS
    fi

    # Check if grype is installed
    if ! command -v grype &> /dev/null; then
        SECURITY_STATUS="unavailable"
        log_warning "⚠️  Grype not found. Install with: brew install --cask grype"
        log_message "   Skipping security vulnerability scan"
        return $EXIT_SUCCESS
    fi

    log_message "🔒 Running security vulnerability scan..."

    local security_file="${LOG_FILE%.log}.security.log"
    local security_json="${LOG_FILE%.log}.security.json"
    local security_detailed="${LOG_FILE%.log}.security.detailed.log"
    local vuln_count=0

    # Run grype scan with severity filtering
    if [[ "$DRY_RUN" == true ]]; then
        SECURITY_STATUS="dry_run"
        log_message "🔍 DRY RUN: Would scan for vulnerabilities (severity: $SECURITY_SCAN_SEVERITY)"
        return $EXIT_SUCCESS
    fi

    # Scan Homebrew Cellar for vulnerabilities (table format for quick view)
    log_verbose "Scanning $(brew --prefix)/Cellar for vulnerabilities..."
    # Exit code intentionally ignored - vulnerabilities are informational, not fatal
    # shellcheck disable=SC2015  # Using short-circuit OR for intentional non-critical behavior
    grype dir:"$(brew --prefix)/Cellar" --only-fixed -q > "$security_file" 2>&1 && true || true

    # Also generate JSON output for detailed analysis with file paths
    # Note: JSON scan can take longer, run in background if needed
    if command -v jq &> /dev/null; then
        log_verbose "Generating detailed vulnerability report with file paths..."
        # Grype writes PURL errors and other messages to stderr, filter them out
        local grype_json_tmp="${security_json}.tmp"
        if grype dir:"$(brew --prefix)/Cellar" --only-fixed -o json 2>&1 | grep -v "^error purl\|^\[" > "$grype_json_tmp" && [[ -s "$grype_json_tmp" ]]; then
            # Parse JSON to create detailed report with file paths
            {
                echo "VULNERABILITY REPORT WITH FILE PATHS"
                echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
                echo "=================================================="
                echo ""

                jq -r '.matches[] |
                    select(.vulnerability.severity == "Critical" or
                           .vulnerability.severity == "High" or
                           .vulnerability.severity == "Medium") |
                    "PACKAGE: \(.artifact.name)
VERSION: \(.artifact.version)
CVE: \(.vulnerability.id)
SEVERITY: \(.vulnerability.severity)
FIXED IN: \(.vulnerability.fix.versions // ["No fix available"] | join(", "))
FILE PATH: \(.artifact.locations[0].path // "N/A")
HOMEBREW PACKAGE: \(.artifact.locations[0].path // "" | split("/") | .[4] // "Unknown")
---"' "$grype_json_tmp" 2>/dev/null
            } > "$security_detailed"

            # Move clean JSON to final location
            mv "$grype_json_tmp" "$security_json"
        else
            log_verbose "JSON security scan did not complete successfully"
            rm -f "$grype_json_tmp"
        fi
    else
        log_verbose "jq not found - detailed vulnerability report not generated"
    fi

    # Count vulnerabilities found
    if [[ -f "$security_file" ]]; then
        # Count lines that match severity levels (excluding header and errors)
        # awk (not grep | wc -l): grep exits 1 when a clean scan matches nothing, which pipefail
        # + set -e would turn into a failed run
        vuln_count=$(awk '/Critical|High|Medium/ && !/^NAME/ && !/^error purl/ { n++ } END { print n + 0 }' \
            "$security_file" 2>/dev/null || echo 0)
        SECURITY_STATUS="completed"
        SECURITY_VULN_COUNT="$vuln_count"

        if [[ $vuln_count -gt 0 ]]; then
            log_warning "⚠️  Found $vuln_count known vulnerabilities with fixes available"
            log_message "Severity filter: $SECURITY_SCAN_SEVERITY"
            echo -e "  ${YELLOW}Severity filter: $SECURITY_SCAN_SEVERITY${NC}"
            echo -e "  ${BLUE}Summary report: $(create_clickable_link "$security_file")${NC}"

            if [[ -f "$security_detailed" ]] && [[ -s "$security_detailed" ]] && [[ $(wc -l < "$security_detailed") -gt 5 ]]; then
                echo -e "  ${BLUE}Detailed report with file paths: $(create_clickable_link "$security_detailed")${NC}"
            fi

            # Show and LOG top vulnerabilities (filter out grype errors).
            # awk reads all of its input: piping a large report into `head` makes the writer
            # die of SIGPIPE, which pipefail + set -e turned into a failed run (exit 141).
            local top_vulns
            top_vulns=$(awk '/Critical|High|Medium/ && !/^NAME/ && !/^error purl/ && shown < 10 { print; shown++ }' \
                "$security_file" 2>/dev/null || true)

            if [[ -n "$top_vulns" ]]; then
                log_message "🔒 Top security vulnerabilities found:"
                echo "$top_vulns" | while IFS= read -r line; do
                    log_message "  $line"
                done
            fi

            # Always show top 10 in console (even without verbose)
            echo -e "\n  ${YELLOW}Top vulnerabilities:${NC}"
            echo "$top_vulns" | while IFS= read -r line; do
                echo -e "  $line"
            done

            # Parse detailed report for actionable info if available
            if [[ -f "$security_detailed" ]]; then
                local package_summary
                # `|| true`: grep finding nothing is not an error (same SIGPIPE reasoning as above for awk)
                package_summary=$(grep "^HOMEBREW PACKAGE:" "$security_detailed" 2>/dev/null | sort -u | awk 'NR <= 5' || true)
                if [[ -n "$package_summary" ]]; then
                    log_message "📦 Affected Homebrew packages:"
                    echo "$package_summary" | while IFS= read -r line; do
                        log_message "  $line"
                    done
                fi
            fi

            # Suggest running brew upgrade
            echo -e "\n  ${GREEN}💡 Tip: Run 'brew upgrade' to update vulnerable packages${NC}"
            log_message "💡 Tip: Run 'brew upgrade' to update vulnerable packages"
        else
            log_success "✓ No known vulnerabilities found (severity: $SECURITY_SCAN_SEVERITY)"
            log_verbose "Full scan report: $security_file"
        fi
    else
        SECURITY_STATUS="failed"
        log_warning "Could not generate security report"
    fi

    # Return success - vulnerabilities are informational
    return $EXIT_SUCCESS
}

cleanup_homebrew() {
    if [[ "$SKIP_CLEANUP" == true ]]; then
        CLEANUP_STATUS="skipped"
        log_message "⏭️  Skipping cleanup (--skip-cleanup)"
        return $EXIT_SUCCESS
    fi

    log_message "4️⃣  Cleaning up Homebrew..."

    if [[ "$DRY_RUN" == true ]]; then
        CLEANUP_STATUS="dry_run"
        log_message "🔍 DRY RUN: Would run cleanup"
        if ! brew cleanup --dry-run 2>/dev/null; then
            log_warning "Could not generate cleanup preview"
        fi
        return $EXIT_SUCCESS
    fi

    # Main cleanup
    if run_with_retry "brew cleanup --prune=all" "cleanup"; then
        CLEANUP_STATUS="completed"
        log_success "✓ Cleanup completed"
    else
        CLEANUP_STATUS="issues"
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
    HOMEBREW_VERSION="$(brew --version 2>/dev/null | head -1 || true)"
    log_message "📊 System Information:"
    log_message "  Homebrew: $HOMEBREW_VERSION"

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

    # Upgrade log if it exists
    local upgrade_file="${LOG_FILE%.log}.upgrades.log"
    if [[ -f "$upgrade_file" ]]; then
        echo -n "  📦 Upgrade Details: "
        create_clickable_link "$upgrade_file"
    fi

    # Security reports if they exist
    local security_file="${LOG_FILE%.log}.security.log"
    local security_detailed="${LOG_FILE%.log}.security.detailed.log"
    if [[ -f "$security_file" ]]; then
        echo -n "  🔒 Security Scan: "
        create_clickable_link "$security_file"
    fi
    if [[ -f "$security_detailed" ]]; then
        echo -n "  🔍 Security Details: "
        create_clickable_link "$security_detailed"
    fi

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
    if [[ -f "$upgrade_file" ]]; then
        echo -e "  ${GREEN}open \"$upgrade_file\"${NC}  # Open upgrade details"
    fi
    if [[ -f "$security_detailed" ]]; then
        echo -e "  ${GREEN}open \"$security_detailed\"${NC}  # Open security details"
    fi
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
# Run Summary (machine-readable output for the UI)
###################
json_escape() {
    local s="$1"
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//$'\t'/\\t}
    s=${s//$'\r'/\\r}
    s=${s//$'\n'/\\n}
    printf '%s' "$s"
}

json_string() {
    printf '"%s"' "$(json_escape "$1")"
}

# JSON string or null for an optional file path
json_file() {
    if [[ -f "$1" ]]; then
        json_string "$1"
    else
        printf 'null'
    fi
}

# JSON array of strings from a space-separated list
json_names() {
    local out="" name
    for name in $1; do
        out+="${out:+,}$(json_string "$name")"
    done
    printf '[%s]' "$out"
}

# JSON array of {name, from, to} objects for the given names, using OUTDATED_DETAILS versions
json_packages() {
    local out="" name record installed available
    for name in $1; do
        record="$(awk -F'|' -v n="$name" '$1 == n { print; exit }' <<< "$OUTDATED_DETAILS")"
        IFS='|' read -r _ installed available <<< "$record"
        out+="${out:+,}{\"name\":$(json_string "$name"),\"from\":$(json_string "${installed:-}"),\"to\":$(json_string "${available:-}")}"
    done
    printf '[%s]' "$out"
}

# Epoch seconds -> ISO 8601 UTC (BSD date uses -r, GNU date uses -d @epoch)
iso_utc() {
    date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ
}

# Written from the EXIT trap so every run that held the lock leaves a summary, even on failure.
# Format documented in docs/run-summary-schema.md - bump SUMMARY_SCHEMA_VERSION on breaking changes.
write_run_summary() {
    local exit_code="$1"
    local end_epoch status
    end_epoch="$(date +%s)"

    if [[ $exit_code -eq 130 || $exit_code -eq 143 ]]; then
        status="cancelled"
    elif [[ "$RUN_COMPLETED" != true ]]; then
        status="failed"
    elif [[ $exit_code -ne 0 || -n "${FAILED_FORMULAE}${FAILED_CASKS}" ]]; then
        status="partial"
    else
        status="success"
    fi

    local base="${LOG_FILE%.log}"
    local tmp_file="${SUMMARY_FILE}.tmp"

    cat > "$tmp_file" << EOF
{
  "schema_version": ${SUMMARY_SCHEMA_VERSION},
  "script_version": $(json_string "$SCRIPT_VERSION"),
  "run_id": $(json_string "$RUN_ID"),
  "trigger": $(json_string "${RUN_TRIGGER:-manual}"),
  "started_at": $(json_string "$(iso_utc "$RUN_START_EPOCH")"),
  "finished_at": $(json_string "$(iso_utc "$end_epoch")"),
  "duration_seconds": $((end_epoch - RUN_START_EPOCH)),
  "status": $(json_string "$status"),
  "exit_code": ${exit_code},
  "dry_run": ${DRY_RUN},
  "options": {
    "skip_casks": ${SKIP_CASKS},
    "skip_cleanup": ${SKIP_CLEANUP},
    "skip_security_scan": ${SKIP_SECURITY_SCAN},
    "packages": $(json_names "$REQUESTED_PACKAGES")
  },
  "homebrew_version": $(json_string "$HOMEBREW_VERSION"),
  "outdated": {
    "formulae": $(json_packages "$OUTDATED_FORMULAE"),
    "casks": $(json_packages "$OUTDATED_CASKS")
  },
  "upgraded": {
    "formulae": $(json_packages "$UPGRADED_FORMULAE"),
    "casks": $(json_packages "$UPGRADED_CASKS")
  },
  "failed": {
    "formulae": $(json_names "$FAILED_FORMULAE"),
    "casks": $(json_names "$FAILED_CASKS")
  },
  "skipped": {
    "excluded": $(json_names "$SKIPPED_EXCLUDED"),
    "pinned": $(json_names "$SKIPPED_PINNED"),
    "not_outdated": $(json_names "$SKIPPED_NOT_OUTDATED")
  },
  "backup": {
    "created": ${BACKUP_CREATED},
    "path": $(json_file "$BACKUP_FILE")
  },
  "doctor": { "status": $(json_string "$DOCTOR_STATUS") },
  "security": {
    "status": $(json_string "$SECURITY_STATUS"),
    "vulnerability_count": ${SECURITY_VULN_COUNT:-0}
  },
  "cleanup": { "status": $(json_string "$CLEANUP_STATUS") },
  "files": {
    "log": $(json_file "$LOG_FILE"),
    "upgrades_log": $(json_file "${base}.upgrades.log"),
    "doctor_log": $(json_file "${base}.doctor.log"),
    "security_log": $(json_file "${base}.security.log"),
    "security_detailed_log": $(json_file "${base}.security.detailed.log"),
    "security_json": $(json_file "${base}.security.json")
  }
}
EOF
    # Atomic rename so readers never see a partial file
    mv "$tmp_file" "$SUMMARY_FILE"
}

###################
# Main Function
###################
main() {
    local exit_code=$EXIT_SUCCESS

    # Parse command line arguments first (needed for setup)
    parse_arguments "$@"

    # Exit before touching any files if another run holds the lock
    acquire_lock || exit $?
    detect_trigger

    print_header
    setup_directories

    # Load configuration after directories are created, and before log cleanup so
    # LOG_RETENTION_DAYS from the config file is honored
    load_config
    cleanup_old_logs
    log_verbose "Run ${RUN_ID} (trigger: ${RUN_TRIGGER}, version: ${SCRIPT_VERSION})"
    [[ -n "$REQUESTED_PACKAGES" ]] && log_message "🎯 Limiting upgrade to: $REQUESTED_PACKAGES"

    # Send start notification
    send_notification "Homebrew Update" "Starting Homebrew update process..." "Submarine"

    # Pre-flight checks
    check_homebrew
    check_prerequisites
    show_system_info
    print_separator

    # System health checks with proper error handling
    local disk_status
    disk_status=0

    # Network check is non-fatal, log warning and continue
    # shellcheck disable=SC2015  # Using short-circuit OR for intentional non-critical behavior
    check_network && true || log_warning "🌐 Continuing despite network issues..."

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

    # Update process (capture the status with || - inside `if ! cmd` $? is always 0)
    update_homebrew || {
        exit_code=$?
        log_error "Homebrew update failed"
        exit "$exit_code"
    }

    # Check for updates and upgrade if available
    if check_outdated_packages; then
        show_upgrade_preview
        upgrade_packages || {
            exit_code=$?
            log_warning "Some package upgrades failed (exit code: $exit_code)"
        }
    else
        log_verbose "No package updates needed, skipping upgrade phase"
    fi

    print_separator

    # Maintenance and Security
    run_doctor
    run_security_scan
    if ! cleanup_homebrew; then
        log_warning "Cleanup encountered issues but continuing..."
    fi

    # Summary
    show_final_summary
    RUN_COMPLETED=true

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

#!/bin/bash

# Uninstall script for Homebrew Update Assistant
# This script safely removes all installed components

set -e  # Exit on error
set -u  # Exit on undefined variable

# Colors for output
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Paths
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly DEST_SCRIPT="${HOME}/bin/brew-updates.command"
readonly LAUNCHAGENT_PLIST="${HOME}/Library/LaunchAgents/com.user.brew-update.plist"
readonly LOG_DIR="${HOME}/.brew_logs"
readonly BACKUP_DIR="${HOME}/.brew_backups"
readonly CONFIG_FILE="${HOME}/.brew_update_config"

# Flags
REMOVE_LOGS=false
REMOVE_BACKUPS=false
REMOVE_CONFIG=false
FORCE=false
DRY_RUN=false

# Helper functions
print_header() {
    echo -e "\n${RED}🗑️  Homebrew Update Assistant - Uninstall${NC}"
    echo -e "${RED}==========================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_dry_run() {
    echo -e "${YELLOW}[DRY RUN] $1${NC}"
}

show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Uninstall the Homebrew Update Assistant and optionally remove data files.

OPTIONS:
    --logs              Remove log files (~/.brew_logs)
    --backups           Remove backup files (~/.brew_backups)
    --config            Remove configuration file (~/.brew_update_config)
    --all               Remove everything (logs, backups, config)
    --dry-run           Show what would be removed without actually removing
    --force             Skip confirmation prompts
    -h, --help          Show this help message

EXAMPLES:
    $(basename "$0")                    # Uninstall script and LaunchAgent only
    $(basename "$0") --all              # Remove everything including data
    $(basename "$0") --logs --backups   # Remove logs and backups but keep config
    $(basename "$0") --dry-run --all    # Preview what would be removed

NOTES:
    By default, only the script and LaunchAgent are removed.
    Your logs, backups, and config are preserved unless explicitly requested.
EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --logs)
                REMOVE_LOGS=true
                shift
                ;;
            --backups)
                REMOVE_BACKUPS=true
                shift
                ;;
            --config)
                REMOVE_CONFIG=true
                shift
                ;;
            --all)
                REMOVE_LOGS=true
                REMOVE_BACKUPS=true
                REMOVE_CONFIG=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage >&2
                exit 1
                ;;
        esac
    done
}

confirm_uninstall() {
    if [[ "$FORCE" == true || "$DRY_RUN" == true ]]; then
        return 0
    fi

    echo -e "${YELLOW}⚠️  WARNING: This will uninstall the Homebrew Update Assistant${NC}\n"

    echo "The following will be removed:"
    echo "  • Script: $DEST_SCRIPT"
    echo "  • LaunchAgent: $LAUNCHAGENT_PLIST"

    if [[ "$REMOVE_LOGS" == true ]]; then
        echo "  • Log directory: $LOG_DIR"
    fi

    if [[ "$REMOVE_BACKUPS" == true ]]; then
        echo "  • Backup directory: $BACKUP_DIR"
    fi

    if [[ "$REMOVE_CONFIG" == true ]]; then
        echo "  • Config file: $CONFIG_FILE"
    fi

    echo -e "\n${BLUE}The following will be preserved:${NC}"
    [[ "$REMOVE_LOGS" == false ]] && echo "  • Logs: $LOG_DIR"
    [[ "$REMOVE_BACKUPS" == false ]] && echo "  • Backups: $BACKUP_DIR"
    [[ "$REMOVE_CONFIG" == false ]] && echo "  • Config: $CONFIG_FILE"

    echo ""
    read -p "$(echo -e ${YELLOW}Are you sure you want to continue? [y/N]:${NC} )" -r response
    case "$response" in
        [Yy]|[Yy][Ee][Ss])
            return 0
            ;;
        *)
            echo -e "\n${GREEN}Uninstall cancelled${NC}"
            exit 0
            ;;
    esac
}

unload_launchagent() {
    echo -e "\n${BLUE}🛑 Stopping LaunchAgent...${NC}"

    if [[ ! -f "$LAUNCHAGENT_PLIST" ]]; then
        print_info "LaunchAgent not found, skipping"
        return 0
    fi

    # Check if LaunchAgent is loaded
    if launchctl list | grep -q "com.user.brew-update"; then
        if [[ "$DRY_RUN" == true ]]; then
            print_dry_run "Would unload LaunchAgent"
        else
            if launchctl unload "$LAUNCHAGENT_PLIST" 2>/dev/null; then
                print_success "LaunchAgent unloaded"
            else
                print_warning "Failed to unload LaunchAgent (may already be unloaded)"
            fi
        fi
    else
        print_info "LaunchAgent not running"
    fi
}

remove_launchagent() {
    echo -e "\n${BLUE}🗑️  Removing LaunchAgent...${NC}"

    if [[ ! -f "$LAUNCHAGENT_PLIST" ]]; then
        print_info "LaunchAgent file not found, skipping"
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        print_dry_run "Would remove: $LAUNCHAGENT_PLIST"
    else
        # Create backup before removing
        local backup_file="${LAUNCHAGENT_PLIST}.removed.$(date +%Y%m%d_%H%M%S)"
        cp "$LAUNCHAGENT_PLIST" "$backup_file" 2>/dev/null || true

        if rm -f "$LAUNCHAGENT_PLIST"; then
            print_success "LaunchAgent removed"
            print_info "Backup saved: $backup_file"
        else
            print_error "Failed to remove LaunchAgent"
            return 1
        fi
    fi
}

remove_script() {
    echo -e "\n${BLUE}🗑️  Removing installed script...${NC}"

    if [[ ! -f "$DEST_SCRIPT" ]]; then
        print_info "Script not found at $DEST_SCRIPT, skipping"
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        print_dry_run "Would remove: $DEST_SCRIPT"
    else
        # Create backup before removing
        local backup_file="${DEST_SCRIPT}.removed.$(date +%Y%m%d_%H%M%S)"
        cp "$DEST_SCRIPT" "$backup_file" 2>/dev/null || true

        if rm -f "$DEST_SCRIPT"; then
            print_success "Script removed"
            print_info "Backup saved: $backup_file"
        else
            print_error "Failed to remove script"
            return 1
        fi
    fi
}

remove_logs() {
    if [[ "$REMOVE_LOGS" == false ]]; then
        return 0
    fi

    echo -e "\n${BLUE}🗑️  Removing log files...${NC}"

    if [[ ! -d "$LOG_DIR" ]]; then
        print_info "Log directory not found, skipping"
        return 0
    fi

    # Count files
    local log_count=$(find "$LOG_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')
    local log_size=$(du -sh "$LOG_DIR" 2>/dev/null | cut -f1)

    if [[ "$DRY_RUN" == true ]]; then
        print_dry_run "Would remove $log_count log files ($log_size)"
        print_dry_run "Directory: $LOG_DIR"
    else
        if rm -rf "$LOG_DIR"; then
            print_success "Removed $log_count log files ($log_size)"
        else
            print_error "Failed to remove log directory"
            return 1
        fi
    fi
}

remove_backups() {
    if [[ "$REMOVE_BACKUPS" == false ]]; then
        return 0
    fi

    echo -e "\n${BLUE}🗑️  Removing backup files...${NC}"

    if [[ ! -d "$BACKUP_DIR" ]]; then
        print_info "Backup directory not found, skipping"
        return 0
    fi

    # Count files
    local backup_count=$(find "$BACKUP_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')
    local backup_size=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)

    if [[ "$DRY_RUN" == true ]]; then
        print_dry_run "Would remove $backup_count backup files ($backup_size)"
        print_dry_run "Directory: $BACKUP_DIR"
    else
        if rm -rf "$BACKUP_DIR"; then
            print_success "Removed $backup_count backup files ($backup_size)"
        else
            print_error "Failed to remove backup directory"
            return 1
        fi
    fi
}

remove_config() {
    if [[ "$REMOVE_CONFIG" == false ]]; then
        return 0
    fi

    echo -e "\n${BLUE}🗑️  Removing configuration file...${NC}"

    if [[ ! -f "$CONFIG_FILE" ]]; then
        print_info "Config file not found, skipping"
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        print_dry_run "Would remove: $CONFIG_FILE"
    else
        # Create backup before removing
        local backup_file="${CONFIG_FILE}.removed.$(date +%Y%m%d_%H%M%S)"
        cp "$CONFIG_FILE" "$backup_file" 2>/dev/null || true

        if rm -f "$CONFIG_FILE"; then
            print_success "Config file removed"
            print_info "Backup saved: $backup_file"
        else
            print_error "Failed to remove config file"
            return 1
        fi
    fi
}

show_summary() {
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "\n${YELLOW}📋 Dry Run Complete${NC}"
        echo -e "${BLUE}No files were actually removed. Run without --dry-run to proceed.${NC}\n"
        return 0
    fi

    echo -e "\n${GREEN}✅ Uninstall completed successfully!${NC}"

    echo -e "\n${BLUE}📋 What was removed:${NC}"
    echo "  ✓ Script: ~/bin/brew-updates.command"
    echo "  ✓ LaunchAgent: com.user.brew-update"

    if [[ "$REMOVE_LOGS" == true ]]; then
        echo "  ✓ Log files: $LOG_DIR"
    fi

    if [[ "$REMOVE_BACKUPS" == true ]]; then
        echo "  ✓ Backup files: $BACKUP_DIR"
    fi

    if [[ "$REMOVE_CONFIG" == true ]]; then
        echo "  ✓ Config file: $CONFIG_FILE"
    fi

    # Show what was preserved
    local preserved=()
    [[ "$REMOVE_LOGS" == false && -d "$LOG_DIR" ]] && preserved+=("Logs: $LOG_DIR")
    [[ "$REMOVE_BACKUPS" == false && -d "$BACKUP_DIR" ]] && preserved+=("Backups: $BACKUP_DIR")
    [[ "$REMOVE_CONFIG" == false && -f "$CONFIG_FILE" ]] && preserved+=("Config: $CONFIG_FILE")

    if [[ ${#preserved[@]} -gt 0 ]]; then
        echo -e "\n${BLUE}📦 Preserved files:${NC}"
        for item in "${preserved[@]}"; do
            echo "  • $item"
        done
        echo -e "\n${YELLOW}💡 To remove these later, run:${NC}"
        [[ "$REMOVE_LOGS" == false ]] && echo "  rm -rf $LOG_DIR"
        [[ "$REMOVE_BACKUPS" == false ]] && echo "  rm -rf $BACKUP_DIR"
        [[ "$REMOVE_CONFIG" == false ]] && echo "  rm -f $CONFIG_FILE"
    fi

    echo -e "\n${BLUE}♻️  To reinstall:${NC}"
    echo "  cd $PROJECT_ROOT"
    echo "  ./scripts/setup.sh"
    echo ""
}

# Main execution
main() {
    print_header

    # Parse arguments
    parse_arguments "$@"

    # Confirm uninstall
    confirm_uninstall

    if [[ "$DRY_RUN" == true ]]; then
        echo -e "\n${YELLOW}🔍 DRY RUN MODE - No changes will be made${NC}"
    fi

    # Perform uninstall steps
    unload_launchagent
    remove_launchagent
    remove_script
    remove_logs
    remove_backups
    remove_config

    # Show summary
    show_summary
}

# Run main function
main "$@"

#!/bin/bash

# Setup script for Homebrew Update Assistant
# This script:
# 1. Copies the latest brew-updates.command to ~/bin
# 2. Installs the LaunchAgent (an existing one is kept so its schedule survives re-deploys)
# 3. Ensures all required directories exist
#
# Options:
#   --reset-launchagent   Regenerate the LaunchAgent plist with defaults (daily 3:00 AM)
#   --uninstall           Remove the installation

set -e  # Exit on error
set -u  # Exit on undefined variable

# Check for --uninstall flag first
if [[ "${1:-}" == "--uninstall" ]]; then
    UNINSTALL_SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/uninstall.sh"
    if [[ -f "$UNINSTALL_SCRIPT_PATH" ]]; then
        exec "$UNINSTALL_SCRIPT_PATH" "${@:2}"  # Pass remaining arguments to uninstall.sh
    else
        echo "Error: uninstall.sh not found at $UNINSTALL_SCRIPT_PATH" >&2
        exit 1
    fi
fi

# Colors for output
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly PROJECT_ROOT
readonly SOURCE_SCRIPT="${PROJECT_ROOT}/brew-updates.command"
readonly DEST_SCRIPT="${HOME}/bin/brew-updates.command"
readonly LAUNCHAGENT_LABEL="com.user.brew-update"
readonly LAUNCHAGENT_PLIST="${HOME}/Library/LaunchAgents/${LAUNCHAGENT_LABEL}.plist"
LAUNCHAGENT_DOMAIN="gui/$(id -u)"
readonly LAUNCHAGENT_DOMAIN
readonly LOG_DIR="${HOME}/.brew_logs"
readonly BACKUP_DIR="${HOME}/.brew_backups"
readonly CONFIG_FILE="${HOME}/.brew_update_config"

RESET_LAUNCHAGENT=false
for arg in "$@"; do
    case "$arg" in
        --reset-launchagent)
            RESET_LAUNCHAGENT=true
            ;;
        -h|--help)
            echo "Usage: $(basename "$0") [--reset-launchagent] [--uninstall [options]]"
            echo "  --reset-launchagent  Regenerate the LaunchAgent with defaults (daily 3:00 AM),"
            echo "                       discarding any custom schedule"
            exit 0
            ;;
        *)
            echo "Unknown option: $arg" >&2
            exit 1
            ;;
    esac
done
readonly RESET_LAUNCHAGENT

# Helper functions
print_header() {
    echo -e "\n${BLUE}🍺 Homebrew Update Assistant - Setup${NC}"
    echo -e "${BLUE}======================================${NC}\n"
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

# Check if source script exists
check_source_script() {
    if [[ ! -f "$SOURCE_SCRIPT" ]]; then
        print_error "Source script not found: $SOURCE_SCRIPT"
        exit 1
    fi
    print_success "Source script found: $SOURCE_SCRIPT"
}

# Create necessary directories
setup_directories() {
    echo -e "\n${BLUE}📁 Setting up directories...${NC}"

    mkdir -p "${HOME}/bin"
    print_success "Created ~/bin directory"

    mkdir -p "$LOG_DIR"
    print_success "Created log directory: $LOG_DIR"

    mkdir -p "$BACKUP_DIR"
    print_success "Created backup directory: $BACKUP_DIR"

    mkdir -p "$(dirname "$LAUNCHAGENT_PLIST")"
    print_success "Created LaunchAgent directory"
}

# Copy script to ~/bin
install_script() {
    echo -e "\n${BLUE}📦 Installing script to ~/bin...${NC}"

    # Backup existing script if it exists
    if [[ -f "$DEST_SCRIPT" ]]; then
        local backup_file
        backup_file="${DEST_SCRIPT}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$DEST_SCRIPT" "$backup_file"
        print_info "Backed up existing script to: $(basename "$backup_file")"
    fi

    # Copy new script
    cp "$SOURCE_SCRIPT" "$DEST_SCRIPT"
    chmod +x "$DEST_SCRIPT"

    # Verify copy
    if [[ -f "$DEST_SCRIPT" ]]; then
        print_success "Script installed: $DEST_SCRIPT"

        # Show file sizes
        local source_size dest_size
        source_size=$(stat -f%z "$SOURCE_SCRIPT" 2>/dev/null || echo "unknown")
        dest_size=$(stat -f%z "$DEST_SCRIPT" 2>/dev/null || echo "unknown")
        print_info "Source size: ${source_size} bytes, Installed size: ${dest_size} bytes"

        # Compare checksums
        local source_md5 dest_md5
        source_md5=$(md5 -q "$SOURCE_SCRIPT" 2>/dev/null || echo "")
        dest_md5=$(md5 -q "$DEST_SCRIPT" 2>/dev/null || echo "")

        if [[ "$source_md5" == "$dest_md5" ]]; then
            print_success "Checksum verification passed ✓"
        else
            print_warning "Checksum mismatch - copy may have failed"
            return 1
        fi
    else
        print_error "Failed to install script"
        return 1
    fi
}

# Describe the plist's schedule for display (simple daily schedules only)
describe_schedule() {
    local hour minute
    if hour=$(plutil -extract StartCalendarInterval.Hour raw "$LAUNCHAGENT_PLIST" 2>/dev/null) && \
       minute=$(plutil -extract StartCalendarInterval.Minute raw "$LAUNCHAGENT_PLIST" 2>/dev/null); then
        printf 'Daily at %02d:%02d' "$hour" "$minute"
    else
        echo "Custom (see StartCalendarInterval in $(basename "$LAUNCHAGENT_PLIST"))"
    fi
}

# Install the LaunchAgent plist. An existing valid plist is kept as-is so a schedule
# edited by hand or by the UI survives re-deploys; --reset-launchagent regenerates it.
install_launchagent() {
    echo -e "\n${BLUE}⚙️  Configuring LaunchAgent...${NC}"

    local write_plist=true
    if [[ -f "$LAUNCHAGENT_PLIST" ]]; then
        if [[ "$RESET_LAUNCHAGENT" == true ]]; then
            print_info "Resetting LaunchAgent to defaults (--reset-launchagent)"
        elif plutil -lint -s "$LAUNCHAGENT_PLIST" >/dev/null 2>&1; then
            write_plist=false
            print_success "Keeping existing LaunchAgent configuration (schedule preserved)"
        else
            print_warning "Existing LaunchAgent plist is invalid - regenerating"
        fi

        if [[ "$write_plist" == true ]]; then
            local backup_plist
            backup_plist="${LAUNCHAGENT_PLIST}.backup.$(date +%Y%m%d_%H%M%S)"
            cp "$LAUNCHAGENT_PLIST" "$backup_plist"
            print_info "Backed up existing plist to: $(basename "$backup_plist")"
        fi
    fi

    if [[ "$write_plist" == true ]]; then
        cat > "$LAUNCHAGENT_PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Unique identifier for this LaunchAgent -->
    <key>Label</key>
    <string>com.user.brew-update</string>

    <!-- Path to script and arguments -->
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${DEST_SCRIPT}</string>
        <string>--yes</string>
        <string>--verbose</string>
    </array>

    <!-- Environment variables for Homebrew -->
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
        <key>HOME</key>
        <string>${HOME}</string>
        <key>ENABLE_NOTIFICATIONS</key>
        <string>true</string>
    </dict>

    <!-- Daily at 3:00 AM -->
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>3</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>

    <!-- Log output to existing brew logs directory -->
    <key>StandardOutPath</key>
    <string>${LOG_DIR}/launchagent.log</string>
    <key>StandardErrorPath</key>
    <string>${LOG_DIR}/launchagent_error.log</string>

    <!-- Run even if previous instance failed -->
    <key>SuccessfulExit</key>
    <false/>

    <!-- Don't throttle if it runs frequently -->
    <key>ThrottleInterval</key>
    <integer>0</integer>
</dict>
</plist>
EOF
        print_success "Created LaunchAgent configuration"
    fi

    # Reload so launchd picks up the current plist (bootout fails harmlessly if not loaded)
    print_info "Reloading LaunchAgent..."
    launchctl bootout "${LAUNCHAGENT_DOMAIN}/${LAUNCHAGENT_LABEL}" 2>/dev/null || true
    if launchctl bootstrap "$LAUNCHAGENT_DOMAIN" "$LAUNCHAGENT_PLIST" 2>/dev/null; then
        print_success "LaunchAgent loaded successfully"
    else
        print_warning "launchctl bootstrap reported an error - checking status"
    fi

    # Verify it's loaded
    if launchctl print "${LAUNCHAGENT_DOMAIN}/${LAUNCHAGENT_LABEL}" >/dev/null 2>&1; then
        print_success "LaunchAgent is active ✓ ($(describe_schedule))"
    else
        print_warning "LaunchAgent is not loaded - try: launchctl bootstrap ${LAUNCHAGENT_DOMAIN} ${LAUNCHAGENT_PLIST}"
    fi
}

# Create sample config file if it doesn't exist
create_sample_config() {
    echo -e "\n${BLUE}📝 Checking configuration...${NC}"

    if [[ -f "$CONFIG_FILE" ]]; then
        print_info "Config file already exists: $CONFIG_FILE"
        echo "   Current settings:"
        grep -v "^#" "$CONFIG_FILE" | grep -v "^$" | sed 's/^/   /' || echo "   (empty)"
    else
        cat > "$CONFIG_FILE" << 'EOF'
# Homebrew Update Assistant Configuration
# Uncomment and modify settings as needed

# Security scanning
SECURITY_SCAN_ENABLED=true
SECURITY_SCAN_SEVERITY=HIGH,CRITICAL

# Logging
LOG_RETENTION_DAYS=30

# Notifications (macOS only)
ENABLE_NOTIFICATIONS=true

# Backup settings (number of Brewfile backups to keep)
MAX_BACKUP_COUNT=5

# Package exclusions (space-separated)
#EXCLUDED_FORMULAE=""
#EXCLUDED_CASKS=""

# Run defaults
#SKIP_CASKS_BY_DEFAULT=false
#CLEANUP_BY_DEFAULT=true
EOF
        print_success "Created sample config file: $CONFIG_FILE"
        print_info "Edit this file to customize behavior"
    fi
}

# Check dependencies
check_dependencies() {
    echo -e "\n${BLUE}🔍 Checking dependencies...${NC}"

    # Check Homebrew
    if command -v brew &> /dev/null; then
        print_success "Homebrew: $(brew --version | head -1)"
    else
        print_error "Homebrew not found - please install from https://brew.sh"
        exit 1
    fi

    # Check optional dependencies
    if command -v terminal-notifier &> /dev/null; then
        print_success "terminal-notifier: installed (notifications enabled)"
    else
        print_warning "terminal-notifier not found (notifications will use osascript)"
        print_info "Install with: brew install terminal-notifier"
    fi

    if command -v grype &> /dev/null; then
        print_success "grype: $(grype version 2>/dev/null | head -1 || echo 'installed')"
    else
        print_warning "grype not found (security scanning will be skipped)"
        print_info "Install with: brew install --cask grype"
    fi

    if command -v jq &> /dev/null; then
        print_success "jq: installed (detailed security reports enabled)"
    else
        print_warning "jq not found (detailed security reports will be skipped)"
        print_info "Install with: brew install jq"
    fi
}

# Show summary
show_summary() {
    echo -e "\n${GREEN}🎉 Setup completed successfully!${NC}"
    echo -e "\n${BLUE}📋 Summary:${NC}"
    echo "  ✓ Script installed to: $DEST_SCRIPT"
    echo "  ✓ LaunchAgent configured: $LAUNCHAGENT_PLIST"
    echo "  ✓ Schedule: $(describe_schedule)"
    echo "  ✓ Logs directory: $LOG_DIR"
    echo "  ✓ Backups directory: $BACKUP_DIR"
    echo "  ✓ Config file: $CONFIG_FILE"

    echo -e "\n${YELLOW}💡 Quick Commands:${NC}"
    echo "  Test the script now:"
    echo "    ${GREEN}~/bin/brew-updates.command --dry-run --verbose${NC}"
    echo ""
    echo "  Run a full update:"
    echo "    ${GREEN}~/bin/brew-updates.command --yes --verbose${NC}"
    echo ""
    echo "  Check LaunchAgent status:"
    echo "    ${GREEN}launchctl print ${LAUNCHAGENT_DOMAIN}/${LAUNCHAGENT_LABEL}${NC}"
    echo ""
    echo "  Manually trigger LaunchAgent:"
    echo "    ${GREEN}launchctl kickstart ${LAUNCHAGENT_DOMAIN}/${LAUNCHAGENT_LABEL}${NC}"
    echo ""
    echo "  View recent logs:"
    echo "    ${GREEN}tail -50 ${LOG_DIR}/launchagent.log${NC}"
    echo ""
    echo "  Unload LaunchAgent:"
    echo "    ${GREEN}launchctl bootout ${LAUNCHAGENT_DOMAIN}/${LAUNCHAGENT_LABEL}${NC}"
    echo ""
    echo "  Reset LaunchAgent to defaults (daily 3:00 AM):"
    echo "    ${GREEN}./scripts/setup.sh --reset-launchagent${NC}"
    echo ""
    echo "  Uninstall (remove everything):"
    echo "    ${GREEN}./scripts/setup.sh --uninstall --all${NC}"
    echo ""
    echo "  Uninstall (keep data):"
    echo "    ${GREEN}./scripts/uninstall.sh${NC}"
    echo ""
    echo -e "${BLUE}📚 For more information, see README.md and DEPLOYMENT.md${NC}\n"
}

# Main execution
main() {
    print_header

    # Pre-flight checks
    check_source_script
    check_dependencies

    # Setup process
    setup_directories
    install_script
    install_launchagent
    create_sample_config

    # Summary
    show_summary
}

# Run main function
main "$@"

# Homebrew Update Assistant

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![macOS](https://img.shields.io/badge/platform-macOS-blue.svg)](https://www.apple.com/macos/)
[![Linux](https://img.shields.io/badge/platform-Linux-green.svg)](https://www.linux.org/)
[![Bash](https://img.shields.io/badge/shell-bash-4EAA25.svg)](https://www.gnu.org/software/bash/)
[![Homebrew](https://img.shields.io/badge/requires-Homebrew-orange.svg)](https://brew.sh/)

> A comprehensive, enterprise-grade bash script for automating Homebrew updates, package management, and system maintenance with enhanced security, error handling, and user experience.

## 🌟 Overview

The Homebrew Update Assistant is a production-ready script that transforms the tedious process of maintaining Homebrew installations into a streamlined, automated experience. With intelligent error handling, comprehensive logging, and user-friendly output, it's perfect for both casual users and system administrators.

### 🔥 Key Highlights

- **🛡️ Enterprise Security**: Input validation, safe command execution, no eval usage
- **🔄 Intelligent Automation**: Exponential backoff retries, network resilience
- **📊 Smart Diagnostics**: Pre-flight checks, health monitoring, meaningful error reporting
- **🎨 Beautiful UX**: Color-coded output, clickable file links, progress tracking
- **⚙️ Highly Configurable**: Configuration files, environment variables, command-line options

## ✨ Features

### Core Functionality
- 🔄 **Intelligent Updates**: Automated Homebrew updates with retry mechanisms and network resilience
- 📦 **Package Management**: Comprehensive formulae and cask updates with exclusion support
- 🔍 **Preview Mode**: Dry-run capabilities to preview all changes before execution
- 💾 **Smart Backups**: Automatic Brewfile backups with configurable retention policies
- 📊 **System Diagnostics**: Pre-flight checks for disk space, network connectivity, and system health
- 📝 **Advanced Logging**: Multi-level logging with timestamped entries and color-coded output
- 🏥 **Health Monitoring**: Intelligent Homebrew doctor analysis with actionable recommendations
- 🧹 **Intelligent Cleanup**: Automated cleanup with unused dependency removal and cache optimization
- 🔒 **Security Scanning**: Automated vulnerability detection using Grype for all installed packages

### Enhanced Features
- 🎯 **CLI Interface**: Full argument parsing with comprehensive help and examples
- 🎨 **Rich Output**: Terminal-aware color coding and clickable file links
- ⚙️ **Configuration**: Flexible configuration file support with validation
- 🔧 **Granular Control**: Skip casks, cleanup operations, or enable full automation
- 📈 **Progress Tracking**: Real-time indicators and detailed operation summaries
- 🚀 **Cross-Platform**: Enhanced compatibility for macOS and Linux systems
- 🔒 **Security-First**: Comprehensive input validation and safe execution practices

### New in v2.0
- 🔐 **Enhanced Security**: Eliminated eval usage, added input validation, secure command execution
- 🎯 **Better Error Handling**: Specific exit codes, improved retry logic, graceful degradation
- 🖱️ **Clickable Links**: Terminal-aware file links for instant log and backup access
- ⚙️ **Configuration System**: File-based configuration with validation and environment variable support
- 📋 **Smart Doctor Output**: Intelligent parsing of Homebrew doctor warnings with contextual help
- 🎨 **Improved UX**: Better terminal detection, non-blocking automation mode, enhanced output

## 🏗️ Architecture

The Homebrew Update Assistant follows a modular, pipeline-based architecture with comprehensive error handling and logging at every stage.

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Execution Trigger                           │
│                  (User / Cron / LaunchAgent)                        │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    brew-updates.command                             │
│                     (Main Script)                                   │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                ┌────────────┴────────────┐
                │                         │
                ▼                         ▼
    ┌───────────────────┐     ┌───────────────────┐
    │  Configuration    │     │   Environment     │
    │     Loading       │     │    Variables      │
    └─────────┬─────────┘     └─────────┬─────────┘
              │                         │
              └────────────┬────────────┘
                           │
                           ▼
              ┌────────────────────────┐
              │   Pre-flight Checks    │
              │  - Disk space (≥1GB)   │
              │  - Network connectivity│
              │  - Homebrew installed  │
              └────────────┬───────────┘
                           │
                           ▼
              ┌────────────────────────┐
              │  Directory Setup       │
              │  - ~/.brew_logs/       │
              │  - ~/.brew_backups/    │
              │  - Log rotation        │
              └────────────┬───────────┘
                           │
                           ▼
              ┌────────────────────────┐
              │  Backup Creation       │
              │  - Brewfile backup     │
              │  - Timestamp naming    │
              │  - Retention cleanup   │
              └────────────┬───────────┘
                           │
                           ▼
              ┌────────────────────────┐
              │  Homebrew Update       │
              │  - brew update         │
              │  - Retry on failure    │
              │  - Network resilience  │
              └────────────┬───────────┘
                           │
                           ▼
              ┌────────────────────────┐
              │  Package Discovery     │
              │  - Check outdated      │
              │  - Apply exclusions    │
              │  - Filter casks        │
              └────────────┬───────────┘
                           │
                           ▼
              ┌────────────────────────┐
              │  Package Upgrade       │
              │  - Formulae upgrade    │
              │  - Cask upgrade        │
              │  - Error handling      │
              └────────────┬───────────┘
                           │
                           ▼
              ┌────────────────────────┐
              │  Doctor Check          │
              │  - brew doctor         │
              │  - Parse warnings      │
              │  - Save report (.log)  │
              └────────────┬───────────┘
                           │
                           ▼
              ┌────────────────────────┐
              │  Security Scan         │
              │  - Grype scan (Cellar) │
              │  - Generate 3 reports  │
              │  - File path mapping   │
              └────────────┬───────────┘
                           │
                           ▼
              ┌────────────────────────┐
              │  Cleanup               │
              │  - brew cleanup        │
              │  - Remove unused deps  │
              │  - Cache optimization  │
              └────────────┬───────────┘
                           │
                           ▼
              ┌────────────────────────┐
              │  Notifications         │
              │  - macOS alerts        │
              │  - Clickable logs      │
              │  - Status summary      │
              └────────────┬───────────┘
                           │
                           ▼
              ┌────────────────────────┐
              │  Final Summary         │
              │  - Operation results   │
              │  - File locations      │
              │  - Quick commands      │
              └────────────────────────┘
                           │
                           ▼
┌───────────────────────────────────────────────────────────────────┐
│                         Output Files                              │
├───────────────────────────────────────────────────────────────────┤
│  ~/.brew_logs/                                                    │
│  ├── brew_update_YYYYMMDD_HHMMSS.log           # Main log       │
│  ├── brew_update_YYYYMMDD_HHMMSS.upgrades.log  # Upgrade details│
│  ├── brew_update_YYYYMMDD_HHMMSS.doctor.log    # Health check   │
│  ├── brew_update_YYYYMMDD_HHMMSS.security.log  # Vuln scan      │
│  ├── brew_update_YYYYMMDD_HHMMSS.security.json # Raw JSON data  │
│  ├── brew_update_YYYYMMDD_HHMMSS.security.detailed.log # Paths  │
│  ├── launchagent.log                            # LaunchAgent    │
│  └── launchagent_error.log                      # LA errors      │
│                                                                   │
│  ~/.brew_backups/                                                 │
│  └── brew_backup_YYYYMMDD_HHMMSS               # Brewfiles      │
└───────────────────────────────────────────────────────────────────┘
```

### Key Components

- **Configuration System**: Multi-source config (file, env vars, CLI args) with validation
- **Error Handling**: Specific exit codes, exponential backoff retries, graceful degradation
- **Logging**: Timestamped, multi-level logging with color-coded output
- **Security**: Input validation, safe command execution, no eval usage
- **Automation**: LaunchAgent/cron support with notification integration

## 📋 Prerequisites

- **🍺 Homebrew**: Must be installed ([Install Homebrew](https://brew.sh/))
- **🐚 Bash**: Version 4.0 or higher (pre-installed on macOS/Linux)
- **⚡ Optional**: GNU coreutils (`brew install coreutils`) for enhanced timeout functionality

### System Requirements
- **macOS**: 10.12+ (Sierra) or newer
- **Linux**: Any modern distribution with Bash 4.0+
- **Disk Space**: At least 1GB free space recommended
- **Network**: Internet connection for package updates

## 🚀 Quick Start

### Option 1: Clone Repository (Recommended)
```bash
# Clone the repository
git clone https://github.com/johxan/homebrew-update-assistant.git
cd homebrew-update-assistant

# Install with setup script (handles everything automatically)
./scripts/setup.sh
```

The setup script will:
- ✅ Copy `brew-updates.command` to `~/bin/`
- ✅ Install LaunchAgent for daily automation
- ✅ Create necessary directories
- ✅ Set up configuration file
- ✅ Verify all dependencies

### Option 2: Manual Installation
```bash
# Download the script
curl -fsSL https://raw.githubusercontent.com/johxan/homebrew-update-assistant/main/brew-updates.command -o brew-updates.command

# Make it executable
chmod +x brew-updates.command

# Run it
./brew-updates.command
```

### Option 3: System-Wide Installation
```bash
# Install to PATH for system-wide access
sudo curl -fsSL https://raw.githubusercontent.com/johxan/homebrew-update-assistant/main/brew-updates.command -o /usr/local/bin/brew-updates
sudo chmod +x /usr/local/bin/brew-updates

# Run from anywhere
brew-updates --help
```

### Automated Setup (Recommended for Daily Use)

After installation, enable automation:

```bash
cd homebrew-update-assistant
./scripts/setup.sh  # Installs LaunchAgent for daily 3 AM updates
```

**LaunchAgent Features:**
- 🕐 Runs automatically daily at 3:00 AM
- 🔔 macOS notifications for update status
- 📝 Complete logging to `~/.brew_logs/`
- 🔄 Automatic catch-up if Mac was sleeping
- 📦 Detailed package upgrade tracking
- 🔒 Security vulnerability scanning

For detailed deployment and customization options, see [DEPLOYMENT.md](DEPLOYMENT.md).

## 📖 Usage

### Basic Commands

```bash
# Interactive update with user prompts
./brew-updates.command

# Preview what would be updated (safe, no changes made)
./brew-updates.command --dry-run

# Fully automated update (perfect for scripts/cron jobs)
./brew-updates.command --yes --verbose

# Update only formulae, skip casks
./brew-updates.command --skip-casks

# Quick update without cleanup
./brew-updates.command --skip-cleanup --yes
```

### Command-Line Options

| Option | Description |
|--------|-------------|
| `-d, --dry-run` | Show what would be updated without making changes |
| `-v, --verbose` | Enable detailed logging and output |
| `-y, --yes` | Automatically answer yes to all prompts (automation mode) |
| `-s, --skip-casks` | Skip cask updates (formulae only) |
| `-c, --skip-cleanup` | Skip cleanup operations |
| `--skip-security-scan` | Skip vulnerability scanning (requires Grype) |
| `-h, --help` | Show help message with examples |

### Advanced Usage Examples

**Automation & Scheduling:**
```bash
# Cron job (weekly updates on Monday at 9 AM)
0 9 * * 1 /path/to/brew-updates.command --yes --verbose >> ~/brew_auto_update.log 2>&1

# Script integration with error handling
if ./brew-updates.command --yes; then
    echo "✅ Homebrew updated successfully"
else
    echo "❌ Update failed with exit code $?"
fi
```

**Development Workflows:**
```bash
# Preview updates before important work
./brew-updates.command --dry-run --verbose

# Quick formulae-only update for development environments
./brew-updates.command --skip-casks --skip-cleanup --yes

# Verbose update with full diagnostic output
./brew-updates.command --verbose 2>&1 | tee detailed-update.log
```

## ⚙️ Configuration

### Configuration File
Create `~/.brew_update_config` to customize behavior:

```bash
# ~/.brew_update_config
# Homebrew Update Assistant Configuration

# Backup settings
BACKUP_RETENTION_DAYS=30
MAX_BACKUP_COUNT=10

# Log retention
LOG_RETENTION_DAYS=30  # Auto-delete logs older than this

# Update preferences
AUTO_UPGRADE=false
SKIP_CASKS_BY_DEFAULT=false
CLEANUP_BY_DEFAULT=true

# Logging
LOG_LEVEL=INFO  # DEBUG, INFO, WARNING, ERROR

# Notifications (macOS only)
ENABLE_NOTIFICATIONS=true  # Enable macOS notification center alerts

# Security vulnerability scanning
SECURITY_SCAN_ENABLED=true  # Enable vulnerability scanning (requires Grype)
SECURITY_SCAN_SEVERITY=HIGH,CRITICAL  # Severity levels to report: LOW, MEDIUM, HIGH, CRITICAL

# Package exclusions (space-separated)
EXCLUDED_FORMULAE="php@7.4 node@14 python@3.9"
EXCLUDED_CASKS="docker-desktop virtualbox"
```

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `BREW_UPDATE_TIMEOUT` | Command timeout in seconds | 300 |
| `BREW_UPDATE_MAX_RETRIES` | Maximum retry attempts | 3 |
| `BREW_UPDATE_DEBUG` | Enable debug mode | false |
| `ENABLE_NOTIFICATIONS` | Show macOS notifications (LaunchAgent) | false |

```bash
# Example usage with environment variables
export BREW_UPDATE_TIMEOUT=600
export BREW_UPDATE_MAX_RETRIES=5
./brew-updates.command --verbose
```

## 🔒 Security Vulnerability Scanning

### Overview
The Homebrew Update Assistant integrates with [Grype](https://github.com/anchore/grype) to automatically scan all installed Homebrew packages for known security vulnerabilities. This helps you identify and fix security issues before they become problems.

### Setup

**1. Install Grype:**
```bash
brew install --cask grype
```

**2. Enable Security Scanning:**

Add to your `~/.brew_update_config`:
```bash
SECURITY_SCAN_ENABLED=true
SECURITY_SCAN_SEVERITY=HIGH,CRITICAL  # Options: LOW, MEDIUM, HIGH, CRITICAL
```

**3. Run the scan:**
```bash
./brew-updates.command
# or skip the scan for specific runs:
./brew-updates.command --skip-security-scan
```

### Features

- **Automated Scanning**: Runs automatically after Homebrew updates and health checks
- **Severity Filtering**: Focus on critical vulnerabilities only or scan all levels
- **Only Fixed Vulnerabilities**: Reports only issues with available fixes
- **Detailed Reports**: Saves scan results to `.security.log` files for review
- **Non-Blocking**: Vulnerabilities are reported but don't stop the update process
- **Smart Detection**: Automatically skips if Grype is not installed

### Example Output

```bash
🔒 Running security vulnerability scan...
⚠️  Found 47 known vulnerabilities with fixes available
  Severity filter: HIGH,CRITICAL
  Full report: ~/.brew_logs/brew_update_20251109_093231.security.log

  Top vulnerabilities:
  NAME       INSTALLED  FIXED IN  TYPE  VULNERABILITY        SEVERITY
  tzinfo     1.2.2      1.2.10    gem   GHSA-5cm2-9h8c-rvfx  High
  json       1.7.7      2.3.0     gem   GHSA-jphg-qwrw-7w9g  High
  ...

  💡 Tip: Run 'brew upgrade' to update vulnerable packages
```

### Weekly Security Audits

Set up automated weekly scans:

```bash
# Add to crontab (crontab -e)
0 9 * * 1 /path/to/brew-updates.command --yes --verbose
```

Or use a LaunchAgent (see [LaunchAgent Setup](#-launchagent-automation-macos)):

```xml
<!-- Security scans run automatically with regular updates -->
<key>StartCalendarInterval</key>
<dict>
    <key>Weekday</key>
    <integer>1</integer>  <!-- Monday -->
    <key>Hour</key>
    <integer>9</integer>
</dict>
```

### Security Scan Configuration

| Configuration Option | Description | Default |
|---------------------|-------------|---------|
| `SECURITY_SCAN_ENABLED` | Enable/disable vulnerability scanning | `false` |
| `SECURITY_SCAN_SEVERITY` | Comma-separated severity levels to report | `HIGH,CRITICAL` |
| `--skip-security-scan` | Command-line flag to skip scan for one run | N/A |

### Understanding Security Reports

Security scans generate **three types of reports** saved to `~/.brew_logs/`:

1. **Summary Report** (`*.security.log`) - Quick table view:
   - **NAME**: Package name with the vulnerability
   - **INSTALLED**: Currently installed version
   - **FIXED IN**: Version that fixes the vulnerability
   - **TYPE**: Package type (gem, go-module, npm, python, etc.)
   - **VULNERABILITY**: CVE or GHSA identifier
   - **SEVERITY**: Risk level (LOW, MEDIUM, HIGH, CRITICAL)
   - **RISK**: Combined risk score based on exploitability

2. **JSON Report** (`*.security.json`) - Raw data for custom analysis

3. **Detailed Report with File Paths** (`*.security.detailed.log`) - Shows exact file locations:
   ```
   PACKAGE: stdlib
   VERSION: go1.24.5
   CVE: CVE-2025-61723
   SEVERITY: High
   FIXED IN: 1.24.8, 1.25.2
   FILE PATH: /1.13.5/bin/terraform
   HOMEBREW PACKAGE: terraform
   ---
   ```

**Requirements:**
- Detailed reports require `jq` to be installed: `brew install jq`
- If `jq` is not available, only summary and JSON reports are generated

### Finding Parent Packages for Vulnerabilities

Security scans report vulnerabilities in **dependencies** (Ruby gems, Go modules, Python packages), not the Homebrew packages themselves.

**NEW: Automatic File Path Detection**
The detailed security report (`*.security.detailed.log`) now automatically shows which file and Homebrew package contains each vulnerability. No manual searching needed!

**Manual Method (if needed):**
```bash
# Find which packages contain a specific vulnerable dependency
find /opt/homebrew/Cellar -type d -name "PACKAGE_NAME*" 2>/dev/null | \
  sed 's|/opt/homebrew/Cellar/||' | cut -d'/' -f1 | sort -u
```

**Common Vulnerability Mappings:**

| Vulnerable Dependency | Parent Homebrew Package(s) | Fix Command |
|-----------------------|---------------------------|-------------|
| `tzinfo`, `json`, `rexml` (Ruby gems) | `cocoapods`, `ruby` | `brew upgrade cocoapods ruby` |
| `Go stdlib` (Go modules) | `go`, `helm`, `terraform` | `brew upgrade go` |
| `pip`, `urllib3` (Python) | `python@3.x`, `aws-sam-cli`, `awscli`, `azure-cli` | `brew upgrade python@3.12 aws-sam-cli` |
| `cocoapods-downloader` | `cocoapods` | `brew upgrade cocoapods` |
| `playwright` (npm) | `node` | `brew upgrade node` |

**Automated Helper Script:**

The project includes `scripts/fix-vulnerabilities.sh` to automatically upgrade packages with known vulnerabilities:

```bash
# Run the automated fix script
./scripts/fix-vulnerabilities.sh
```

This script will:
- Update Homebrew
- Upgrade all packages with vulnerable dependencies
- Update Python pip and urllib3 across all Python versions
- Run a security scan to verify fixes
- Show remaining vulnerabilities

For more details, see:
- [Vulnerability Fix Quickstart Guide](docs/VULNERABILITY_FIX_QUICKSTART.md)
- [Security Setup Summary](docs/SECURITY_SETUP_SUMMARY.md)

### Best Practices

1. **Enable by Default**: Add `SECURITY_SCAN_ENABLED=true` to your config file
2. **Weekly Scans**: Schedule regular automated scans with LaunchAgent or cron
3. **Review Reports**: Check `.security.log` files for detailed vulnerability information
4. **Understand Dependencies**: Most vulnerabilities are in bundled dependencies, not main packages
5. **Focus on HIGH/CRITICAL**: Don't stress over every MEDIUM/LOW vulnerability
6. **Use Fix Script**: Run `./scripts/fix-vulnerabilities.sh` for automated remediation
7. **Update Promptly**: Run `brew upgrade` to fix identified vulnerabilities
8. **Keep Grype Updated**: Update Grype regularly with `brew upgrade --cask grype`

### Troubleshooting

**Grype not found:**
```bash
brew install --cask grype
# Verify installation:
grype version
```

**Scan taking too long:**
- Grype caches vulnerability databases locally (first run is slower)
- Subsequent scans are much faster
- Consider using `--skip-security-scan` for quick updates

**False positives:**
- Grype uses multiple vulnerability databases
- Some warnings may not apply to your use case
- Review the CVE/GHSA details in the report for context

## 🍎 macOS Integration

### Double-Click Functionality
The script uses the `.command` extension for seamless macOS integration:

- ✅ **Native Support**: Double-click in Finder opens Terminal automatically
- ✅ **No Setup Required**: Works out of the box on all macOS versions
- ✅ **User-Friendly**: Perfect for non-technical users
- ✅ **Terminal Integration**: Shows real-time progress and output

### Creating Desktop Shortcuts
```bash
# Create a desktop shortcut (optional)
ln -s "/path/to/brew-updates.command" "$HOME/Desktop/Update Homebrew.command"
```

### For Windows/Linux Users
Simply rename the file to remove the `.command` extension:
```bash
mv brew-updates.command brew-updates
chmod +x brew-updates
./brew-updates
```

### 🔔 Notifications (macOS)

Get real-time notifications when using LaunchAgent automation!

**Features:**
- 🚀 **Start notification**: Alerts when the update process begins
- 📦 **Update available**: Shows count of packages ready for update
- ✅ **Success notification**: Confirms successful completion
- ⚠️ **Warning notification**: Alerts if issues occurred
- ✨ **Up-to-date notification**: Confirms all packages are current
- 🖱️ **Clickable notifications**: Click to open log folder (requires `terminal-notifier`)

**How to Enable:**

1. **Via LaunchAgent** (recommended for automation):
   - The sample plist includes `ENABLE_NOTIFICATIONS=true` by default
   - Notifications will appear in macOS Notification Center
   - No additional setup required

2. **Enable Clickable Notifications** (optional):
   ```bash
   brew install terminal-notifier
   # Now clicking notifications will open the log folder
   ```

3. **Via Configuration File**:
   ```bash
   # Add to ~/.brew_update_config
   ENABLE_NOTIFICATIONS=true
   ```

4. **Via Environment Variable**:
   ```bash
   export ENABLE_NOTIFICATIONS=true
   ./brew-updates.command --yes
   ```

**Notification Examples:**
- 🔵 "Homebrew Update - Starting Homebrew update process..."
- 📦 "Homebrew Update - 5 package(s) available for update"
- ✅ "Homebrew Update - Update completed successfully!"
- ✨ "Homebrew Update - All packages are up to date!"

**Customization:**
Notifications use native macOS sounds:
- Start: "Submarine" (gentle alert)
- Updates available: "Purr" (notification)
- Success: "Glass" (completion)
- Up-to-date: "Blow" (light chime)
- Warning: "Basso" (error tone)

**Troubleshooting:**
- Ensure System Settings → Notifications → Script Editor (or terminal-notifier) is enabled
- Check "Do Not Disturb" mode is not blocking notifications
- Verify `ENABLE_NOTIFICATIONS=true` is set in your environment
- If notifications aren't clickable, install `terminal-notifier`: `brew install terminal-notifier`

## 📁 File Locations & Structure

### Generated Files
```
~/.brew_logs/                                      # Log directory
├── brew_update_YYYYMMDD_HHMMSS.log               # Main execution log
├── brew_update_YYYYMMDD_HHMMSS.upgrades.log      # Package upgrade details (NEW)
├── brew_update_YYYYMMDD_HHMMSS.doctor.log        # Homebrew doctor report
├── brew_update_YYYYMMDD_HHMMSS.security.log      # Security scan summary
├── brew_update_YYYYMMDD_HHMMSS.security.json     # Security scan raw data
├── brew_update_YYYYMMDD_HHMMSS.security.detailed.log  # Vulnerabilities with file paths
├── launchagent.log                                # LaunchAgent stdout (if enabled)
└── launchagent_error.log                          # LaunchAgent stderr (if enabled)

~/.brew_backups/                       # Backup directory
├── brew_backup_YYYYMMDD_HHMMSS       # Brewfile backups
└── ...                               # (automatic rotation)
```

### Automatic Cleanup
The script automatically manages disk space:
- **Logs**: Automatically deleted after 30 days (configurable via `LOG_RETENTION_DAYS`)
- **Backups**: Keeps last 5 backups by default (configurable via `MAX_BACKUP_COUNT`)
- **Cleanup runs**: Every time the script executes

**Customize retention periods:**
```bash
# In ~/.brew_update_config
LOG_RETENTION_DAYS=60    # Keep logs for 60 days
BACKUP_RETENTION_DAYS=30 # Still used for display purposes
MAX_BACKUP_COUNT=10      # Keep last 10 backups
```

### Clickable File Access
The script provides clickable links for:
- 📝 **Main logs** (execution details)
- 🏥 **Doctor reports** (health analysis)
- 💾 **Backup files** (restore points)
- 📂 **Directory access** (browse all files)
- 🔔 **Notification click** (opens log folder directly)

## 🔧 Advanced Features

### Automation Setup

#### Option 1: macOS LaunchAgent (Recommended for macOS)

LaunchAgents provide native macOS scheduling with better reliability than cron. They automatically catch up on missed runs if your Mac was asleep.

**Quick Setup:**
```bash
# 1. Copy the script to a user-accessible location
mkdir -p ~/bin
cp brew-updates.command ~/bin/
chmod +x ~/bin/brew-updates.command

# 2. Copy the sample plist from examples/ and customize it
cp examples/com.user.brew-update.plist.sample com.user.brew-update.plist

# 3. Edit the plist file and update paths
# - Update USERNAME to your actual username
# - Update SCHEDULE if you want different timing
# - Verify the PATH includes Homebrew location

# 4. Install the LaunchAgent
cp com.user.brew-update.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.user.brew-update.plist

# 5. Test immediately (don't wait for schedule)
launchctl start com.user.brew-update

# 6. Check the logs
tail -f ~/.brew_logs/launchagent.log
```

**Managing LaunchAgent:**
```bash
# Check status (recommended method)
launchctl list com.user.brew-update

# Alternative: Search all LaunchAgents
launchctl list | grep -i brew

# View logs
tail -50 ~/.brew_logs/launchagent.log          # Standard output
tail -50 ~/.brew_logs/launchagent_error.log    # Errors only

# Check when last run
ls -lht ~/.brew_logs/launchagent*.log | head -3

# Stop the LaunchAgent
launchctl unload ~/Library/LaunchAgents/com.user.brew-update.plist

# Restart after configuration changes
launchctl unload ~/Library/LaunchAgents/com.user.brew-update.plist
launchctl load ~/Library/LaunchAgents/com.user.brew-update.plist
```

**Customizing Schedule:**

The included sample runs every Monday at 9:00 AM. To customize, edit your installed plist file:

**File Location:** `~/Library/LaunchAgents/com.user.brew-update.plist`

**Quick Edit:**
```bash
# Open in default text editor
open ~/Library/LaunchAgents/com.user.brew-update.plist

# Or use nano
nano ~/Library/LaunchAgents/com.user.brew-update.plist

# Or use VS Code
code ~/Library/LaunchAgents/com.user.brew-update.plist
```

**Schedule Examples:**

Find the `<key>StartCalendarInterval</key>` section and replace it with one of these:

```xml
<!-- Daily at 3:00 AM -->
<key>StartCalendarInterval</key>
<dict>
    <key>Hour</key>
    <integer>3</integer>
    <key>Minute</key>
    <integer>0</integer>
</dict>

<!-- Every Sunday at noon -->
<key>StartCalendarInterval</key>
<dict>
    <key>Weekday</key>
    <integer>0</integer>  <!-- 0=Sunday, 1=Monday, ..., 6=Saturday -->
    <key>Hour</key>
    <integer>12</integer>
</dict>

<!-- Multiple times per week -->
<key>StartCalendarInterval</key>
<array>
    <dict>
        <key>Weekday</key>
        <integer>1</integer>  <!-- Monday -->
        <key>Hour</key>
        <integer>9</integer>
    </dict>
    <dict>
        <key>Weekday</key>
        <integer>5</integer>  <!-- Friday -->
        <key>Hour</key>
        <integer>17</integer>
    </dict>
</array>
```

**After Editing the Schedule:**

You must reload the LaunchAgent for changes to take effect:

```bash
# Unload the current configuration
launchctl unload ~/Library/LaunchAgents/com.user.brew-update.plist

# Reload with new schedule
launchctl load ~/Library/LaunchAgents/com.user.brew-update.plist

# Verify it's loaded
launchctl list com.user.brew-update
```

**Important Notes:**
- Edit the file at: `~/Library/LaunchAgents/com.user.brew-update.plist` (not the sample)
- The script copy in `~/bin/` is what LaunchAgent will run
- If you update the original script, remember to copy it to `~/bin/` again
- LaunchAgent runs in a minimal environment - PATH is set in the plist
- Logs go to `~/.brew_logs/launchagent.log` and `launchagent_error.log`
- **Notifications enabled by default** - Get macOS alerts for update status (see [Notifications section](#-notifications-macos))

#### Option 2: Cron Job (macOS/Linux)

**Note for macOS users:** On modern macOS, cron requires Full Disk Access permission and LaunchAgents are the recommended approach. Use cron for Linux or if you prefer traditional scheduling.

```bash
# Edit crontab
crontab -e

# Add weekly updates (Monday 9 AM)
0 9 * * 1 /usr/local/bin/brew-updates --yes --verbose >> ~/brew_auto.log 2>&1

# Or use the full path if not installed system-wide
0 9 * * 1 /path/to/brew-updates.command --yes --verbose >> ~/brew_auto.log 2>&1
```

**Cron Schedule Examples:**
```bash
# Daily at 3 AM
0 3 * * * /usr/local/bin/brew-updates --yes

# Every Sunday at midnight
0 0 * * 0 /usr/local/bin/brew-updates --yes

# Twice per week (Monday and Friday at 9 AM)
0 9 * * 1,5 /usr/local/bin/brew-updates --yes
```

### Integration Ideas
- **CI/CD Pipelines**: Automate development environment updates
- **Team Synchronization**: Share configurations across development teams
- **Monitoring Integration**: Send metrics to monitoring systems
- **Notification Systems**: Add Slack/email notifications for completion
- **Git Integration**: Automatically commit Brewfile changes

## 🛡️ Security & Safety

### Security Features
- **🔒 Input Validation**: All user inputs and environment variables are validated
- **🚫 No Eval Usage**: Commands are executed safely without shell injection risks
- **✅ Path Validation**: File paths are sanitized and validated
- **🛡️ Privilege Management**: Runs with user privileges, no unnecessary elevation

### Safety Mechanisms
- **🔍 Pre-flight Checks**: System validation before making changes
- **💾 Automatic Backups**: Restore points created before major operations
- **🔄 Retry Logic**: Exponential backoff for network-related failures
- **📝 Comprehensive Logging**: All operations logged with timestamps
- **⚠️ Graceful Failures**: Continues operation when non-critical components fail

### Error Recovery
- **🎯 Specific Exit Codes**: Different codes for different error types
- **📊 Detailed Error Messages**: Clear information about what went wrong
- **🔧 Recovery Suggestions**: Actionable recommendations for fixing issues
- **📋 Rollback Information**: Clear instructions for restoration if needed

## 🐛 Troubleshooting

### Common Issues

**Network Connection Problems:**
```bash
# The script automatically retries network operations
# If issues persist, check your internet connection
ping -c 3 github.com
```

**Disk Space Issues:**
```bash
# Check available space
df -h $(brew --prefix)

# Clean up manually if needed
brew cleanup --prune=all
```

**Permission Problems:**
```bash
# Fix Homebrew permissions
sudo chown -R $(whoami) $(brew --prefix)/*
```

**Homebrew Doctor Warnings:**
The script now provides contextual help for common warnings:
- **Formula conflicts**: Use full tap names (e.g., `hashicorp/tap/terraform`)
- **Linking issues**: Run `brew link --overwrite <formula>`
- **Cask warnings**: Usually safe to ignore unless specific casks fail

### Getting Help

1. **📊 Check the logs**: Most issues are documented in the log files
2. **🔍 Run with --verbose**: Provides detailed operation information  
3. **🧪 Use --dry-run**: Preview operations without making changes
4. **🏥 Review doctor report**: Homebrew-specific issues are documented
5. **🐛 Submit an issue**: Use GitHub issues for bug reports

### Debug Mode
```bash
# Enable debug output
export BREW_UPDATE_DEBUG=true
./brew-updates.command --verbose
```

## 🤝 Contributing

We welcome contributions! Here's how to get started:

### Development Setup
```bash
# Fork and clone the repository
git clone https://github.com/yourusername/homebrew-update-assistant.git
cd homebrew-update-assistant

# Make the script executable
chmod +x brew-updates.command

# Test your changes
./brew-updates.command --dry-run --verbose
```

### Contribution Guidelines
- **🧪 Test thoroughly**: Ensure changes work across different scenarios
- **📝 Update documentation**: Keep README.md and code comments current
- **🎨 Follow style**: Use existing code style and conventions
- **🔒 Security first**: Validate all inputs and use safe practices

### Types of Contributions Welcome
- 🐛 **Bug fixes**: Fix issues and improve reliability
- ✨ **New features**: Add useful functionality
- 📚 **Documentation**: Improve guides and examples
- 🎨 **UI/UX improvements**: Enhance user experience
- 🔧 **Configuration options**: Add new customization capabilities

For detailed contribution guidelines, see [CONTRIBUTING.md](docs/CONTRIBUTING.md).

## 📁 Project Structure

```
homebrew-update-assistant/
├── brew-updates.command          # Main script (production-ready)
├── scripts/                       # Management and utility scripts
│   ├── setup.sh                   # Automated installation & deployment
│   ├── uninstall.sh               # Clean uninstallation script
│   └── fix-vulnerabilities.sh     # Automated vulnerability remediation
├── com.user.brew-update.plist     # LaunchAgent template
├── README.md                      # This file (complete documentation)
├── DEPLOYMENT.md                  # Deployment and update guide
├── LICENSE                        # MIT License
├── CLAUDE.md                      # Claude Code project instructions
├── docs/                          # Additional documentation
│   ├── CHANGELOG.md              # Version history and changes
│   ├── IMPROVEMENTS.md           # Planned improvements and roadmap
│   ├── CONTRIBUTING.md           # Contribution guidelines
│   ├── SECURITY_SETUP_SUMMARY.md # Security scanning setup guide
│   └── VULNERABILITY_FIX_QUICKSTART.md  # Quick vulnerability fix guide
└── examples/                      # Configuration examples
    ├── brew_update_config.example  # Sample configuration file
    └── com.user.brew-update.plist.sample  # LaunchAgent template (deprecated)
```

### File Descriptions

**Core Files:**
- `brew-updates.command` - Main executable script (~1260 lines)
- `README.md` - Complete documentation and usage guide
- `DEPLOYMENT.md` - Deployment, update, and uninstall guide
- `LICENSE` - MIT License details
- `CLAUDE.md` - Instructions for Claude Code AI assistant

**Management Scripts (scripts/):**
- `setup.sh` - Automated installation and deployment
  - Copies script to `~/bin/`
  - Installs LaunchAgent
  - Creates directories
  - Verifies checksums
- `uninstall.sh` - Clean uninstallation
  - Removes script and LaunchAgent
  - Optional: Remove logs, backups, config
  - Dry-run support
- `fix-vulnerabilities.sh` - Automated vulnerability remediation
  - Updates packages with known vulnerabilities
  - Runs security scans
  - Shows before/after comparison

**Documentation (docs/):**
- `CHANGELOG.md` - Version history, features added, and changes
- `IMPROVEMENTS.md` - Future enhancements and prioritized roadmap
- `CONTRIBUTING.md` - Guidelines for contributors
- `SECURITY_SETUP_SUMMARY.md` - Grype installation and security scanning setup
- `VULNERABILITY_FIX_QUICKSTART.md` - Quick guide to fixing vulnerabilities

**Examples (examples/):**
- `brew_update_config.example` - Sample `~/.brew_update_config` with all options
- `com.user.brew-update.plist.sample` - macOS LaunchAgent template (superseded by setup.sh)

### Runtime Directories

These directories are created automatically in your home directory:

- `~/.brew_logs/` - Log files (`.log`, `.doctor.log`, `.security.log`)
- `~/.brew_backups/` - Brewfile backups with 30-day retention
- `~/.brew_update_config` - Optional user configuration file

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

```
MIT License

Copyright (c) 2024 johxan

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## 👤 Author

**johxan**
- GitHub: [@johxan](https://github.com/johxan)
- Email: [your-email@example.com](mailto:your-email@example.com)

## 🙏 Acknowledgments

- **🍺 Homebrew Team**: For creating and maintaining the excellent Homebrew package manager
- **🌍 Open Source Community**: For inspiration, feedback, and best practices
- **🔧 Contributors**: Everyone who has helped improve this script
- **🧪 Beta Testers**: Users who provided valuable feedback and bug reports

## 📊 Project Statistics

![GitHub stars](https://img.shields.io/github/stars/johxan/homebrew-update-assistant?style=social)
![GitHub forks](https://img.shields.io/github/forks/johxan/homebrew-update-assistant?style=social)
![GitHub issues](https://img.shields.io/github/issues/johxan/homebrew-update-assistant)
![GitHub pull requests](https://img.shields.io/github/issues-pr/johxan/homebrew-update-assistant)

---

<div align="center">

**⭐ If this script helped you, please consider giving it a star! ⭐**

**🍺 Happy Brewing! 🍺**

</div>

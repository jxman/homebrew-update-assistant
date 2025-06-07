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

### Option 1: Direct Download (Recommended)
```bash
# Download the script
curl -fsSL https://raw.githubusercontent.com/johxan/homebrew-update-assistant/main/brew-updates.command -o brew-updates.command

# Make it executable
chmod +x brew-updates.command

# Run it
./brew-updates.command
```

### Option 2: Clone Repository
```bash
# Clone the repository
git clone https://github.com/johxan/homebrew-update-assistant.git
cd homebrew-update-assistant

# Make executable and run
chmod +x brew-updates.command
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

# Update preferences
AUTO_UPGRADE=false
SKIP_CASKS_BY_DEFAULT=false
CLEANUP_BY_DEFAULT=true

# Logging
LOG_LEVEL=INFO  # DEBUG, INFO, WARNING, ERROR

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

```bash
# Example usage with environment variables
export BREW_UPDATE_TIMEOUT=600
export BREW_UPDATE_MAX_RETRIES=5
./brew-updates.command --verbose
```

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

## 📁 File Locations & Structure

### Generated Files
```
~/.brew_logs/                          # Log directory
├── brew_update_YYYYMMDD_HHMMSS.log   # Main execution log
└── brew_update_YYYYMMDD_HHMMSS.log.doctor  # Homebrew doctor report

~/.brew_backups/                       # Backup directory
├── brew_backup_YYYYMMDD_HHMMSS       # Brewfile backups
└── ...                               # (automatic rotation)
```

### Clickable File Access
The script provides clickable links for:
- 📝 **Main logs** (execution details)
- 🏥 **Doctor reports** (health analysis)
- 💾 **Backup files** (restore points)
- 📂 **Directory access** (browse all files)

## 🔧 Advanced Features

### Automation Setup

**Cron Job Example:**
```bash
# Edit crontab
crontab -e

# Add weekly updates (Monday 9 AM)
0 9 * * 1 /usr/local/bin/brew-updates --yes --verbose >> ~/brew_auto.log 2>&1
```

**LaunchAgent (macOS):**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.brew-update</string>
    <key>ProgramArguments</key>
    <array>
        <string>/path/to/brew-updates.command</string>
        <string>--yes</string>
        <string>--verbose</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Weekday</key>
        <integer>1</integer>
        <key>Hour</key>
        <integer>9</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>/Users/username/brew_update.log</string>
    <key>StandardErrorPath</key>
    <string>/Users/username/brew_update.log</string>
</dict>
</plist>
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
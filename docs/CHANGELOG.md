# Changelog

All notable changes to the Homebrew Update Assistant will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.1.0] - 2024-11-08

### 🎉 Feature Release - Automation & Notifications

This version adds comprehensive macOS automation support with LaunchAgent integration and an intelligent notification system for background operations.

### Added
- 🔔 **macOS Notification System**
  - Native macOS notifications for update status and completion
  - Clickable notifications that open log folder (via `terminal-notifier`)
  - Fallback to `osascript` for basic notifications
  - Configurable notification sounds for different events
  - Start, update available, success, warning, and up-to-date notifications
  - Environment variable and config file support for enabling notifications

- 🤖 **LaunchAgent Automation Support**
  - Sample plist configuration for automated scheduling (`com.user.brew-update.plist.sample`)
  - Proper PATH and environment variable configuration
  - Dedicated LaunchAgent logging support
  - Documentation for weekly/custom schedules
  - Integration with notification system for unattended operation

- 📦 **Automatic Log Archiving**
  - Configurable log retention with automatic cleanup
  - Default 30-day retention for log files
  - Cleanup runs automatically during each execution
  - Verbose logging of cleanup operations

- 📝 **Project Documentation**
  - Added `CLAUDE.md` for project-specific AI assistant instructions
  - Comprehensive development standards and testing procedures
  - macOS-specific development preferences
  - Code quality and structure guidelines

### Changed
- 🏥 **Doctor Report File Naming**
  - Changed from `.log.doctor` to `.doctor.log` extension
  - Enables direct opening in macOS Console.app when clicked in Finder
  - More intuitive naming: `brew_update_YYYYMMDD_HHMMSS.doctor.log`
  - All existing doctor files automatically migrated to new format

- 📂 **Repository Structure**
  - Added `.gitignore` rules for user-specific LaunchAgent plist files
  - Excluded personal configuration from version control
  - Cleaner repository with template files only

### Fixed
- 🐛 **LaunchAgent Compatibility**
  - Fixed `ENABLE_NOTIFICATIONS` environment variable handling
  - Resolved `set -e` conflicts with `brew doctor` warnings
  - Fixed `parse_doctor_output` function causing premature exits
  - Added `2>/dev/null` to grep commands for proper error handling
  - Ensured `run_doctor()` always returns success (warnings are informational)

- 🔧 **Notification System**
  - Fixed terminal-notifier path resolution in LaunchAgent environment
  - Added full path (`/opt/homebrew/bin/terminal-notifier`) for reliability
  - Improved notification fallback logic
  - Enhanced verbose logging for notification debugging

### Documentation
- 📖 **README Updates**
  - Added comprehensive notification system documentation
  - Detailed LaunchAgent setup instructions with troubleshooting
  - System Settings permission requirements for terminal-notifier
  - Updated file structure documentation with new naming
  - Added manual LaunchAgent execution instructions

- 🔧 **Configuration Examples**
  - Documented all notification configuration methods
  - Added LaunchAgent environment variable examples
  - Included scheduling examples (weekly, bi-weekly, custom)
  - Troubleshooting section for common notification issues

### Security
- 🔒 **Environment Variable Handling**
  - Improved validation of notification settings
  - Secure handling of PATH in LaunchAgent context
  - Proper escaping in notification messages

## [2.0.0] - 2024-12-06

### 🎉 Major Release - Complete Rewrite

This version represents a complete rewrite of the Homebrew Update Assistant with enterprise-grade security, reliability, and user experience improvements.

### Added
- 🔐 **Enhanced Security Framework**
  - Input validation for all user inputs and environment variables
  - Eliminated unsafe `eval` usage with secure command execution
  - Path sanitization and validation
  - Secure configuration file loading with validation

- 🎯 **Advanced Error Handling**
  - Specific exit codes for different error types (network, disk space, Homebrew errors)
  - Intelligent retry logic with exponential backoff
  - Graceful degradation for non-critical failures
  - Better error recovery and user guidance

- ⚙️ **Configuration System**
  - File-based configuration support (`~/.brew_update_config`)
  - Environment variable validation and override support
  - Package exclusion lists for formulae and casks
  - Configurable backup retention and cleanup settings

- 🖱️ **Interactive Features**
  - Clickable file links for logs and backups (terminal-aware)
  - Terminal capability detection (iTerm2, VS Code, Terminal.app)
  - Smart output formatting based on terminal capabilities
  - Non-blocking automation mode for CI/CD integration

- 📋 **Intelligent Doctor Output**
  - Smart parsing of Homebrew doctor warnings vs errors
  - Contextual help for common issues (formula conflicts, linking problems)
  - User-friendly explanations for technical warnings
  - Detection of informational-only messages

- 🔧 **Enhanced CLI Interface**
  - Improved argument parsing with validation
  - Better help text with practical examples
  - Comprehensive error messages with suggestions
  - Support for `--` argument separator

### Improved
- 🚀 **Performance Optimizations**
  - Eliminated duplicate command executions (autoremove check)
  - Better timeout handling with fallback mechanisms
  - Optimized backup cleanup with safer file operations
  - Parallel-ready architecture for future enhancements

- 🎨 **User Experience**
  - Better progress indicators and status reporting
  - Color-coded output with consistent formatting
  - Improved verbose mode with structured logging
  - Enhanced final summary with actionable file links

- 🛡️ **Reliability Improvements**
  - Better network connectivity handling
  - Enhanced disk space monitoring with specific thresholds
  - Improved backup creation and rotation logic
  - More robust command execution with proper error propagation

### Security
- 🔒 **Critical Security Fixes**
  - Removed all `eval` usage that could lead to command injection
  - Added comprehensive input validation patterns
  - Implemented safe command array execution
  - Enhanced file path validation and sanitization

### Fixed
- 🐛 **Bug Fixes**
  - Fixed inconsistent return code logic in package checking
  - Resolved timeout handling on systems without `gtimeout`
  - Fixed backup cleanup edge cases with special characters
  - Corrected terminal detection for better cross-platform support

### Changed
- 💔 **Breaking Changes**
  - Configuration file format updated (backward compatible values)
  - Some internal function signatures changed (external API unchanged)
  - Error codes standardized (may affect scripts checking specific codes)

### Deprecated
- ⚠️ **Deprecations**
  - Old environment variable names (still supported with warnings)
  - Legacy configuration options (redirected to new equivalents)

## [1.0.0] - 2024-01-01

### Added
- Initial release of Homebrew Update Assistant
- Basic Homebrew update automation
- Simple backup creation
- Command-line argument support
- Basic error handling and logging
- macOS `.command` extension support
- Color-coded terminal output
- Dry-run mode for preview functionality

### Features
- Automatic Homebrew updates
- Package upgrade management
- Basic cleanup operations
- Simple logging system
- Interactive confirmation prompts

---

## Migration Guide

### Upgrading from v1.x to v2.x

#### Configuration Changes
If you were using environment variables in v1.x:
```bash
# Old (still works with deprecation warning)
export TIMEOUT=600

# New (recommended)
export BREW_UPDATE_TIMEOUT=600
```

#### Script Behavior
- The script now validates all inputs by default
- Error handling is more strict (may catch issues that were previously ignored)
- Backup retention is now configurable (defaults to 5 backups instead of fixed)

#### New Configuration File
Create `~/.brew_update_config` to customize behavior:
```bash
# Example configuration
MAX_BACKUP_COUNT=10
EXCLUDED_FORMULAE="php@7.4 node@14"
LOG_LEVEL=INFO
```

---

## Upcoming Features

### Planned for v2.2.0
- [ ] LaunchAgent installer/uninstaller scripts for easy setup
- [ ] Configuration validation and generation commands
- [ ] Version and system info commands
- [ ] Git integration for automatic Brewfile commits
- [ ] Enhanced progress bars and status indicators
- [ ] Update history tracking and analytics
- [ ] Monthly summary reports

### Planned for v2.3.0
- [ ] Web dashboard for update monitoring
- [ ] Advanced package filtering and policies
- [ ] Integration with CI/CD platforms
- [ ] Custom hook system for pre/post operations
- [ ] Automated testing suite
- [ ] GitHub Actions CI/CD

### Completed Features
- ✅ Notification system integration (v2.1.0) - macOS native notifications
- ✅ Package update scheduling and policies (v2.1.0) - LaunchAgent support
- ✅ Automatic log archiving (v2.1.0) - 30-day retention

---

**Full Changelog**: https://github.com/jxman/homebrew-update-assistant/compare/v1.0.0...v2.1.0
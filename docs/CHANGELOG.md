# Changelog

All notable changes to the Homebrew Update Assistant will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### SwiftUI App

#### Added
- Toolbar: separate **Dry Run** and **Update All** buttons with text labels (Update All shows
  how many packages it will upgrade), replacing the icon-only button whose Dry Run was hidden
  behind a small arrow. New **Run** menu with Dry Run (⇧⌘U), Update All… (⌘U) and Stop (⌘.)
- Help window (Help → Brew Updates Help, ⌘?, or Help in the menu bar menu) with a page per
  section plus Getting Started, Settings and Troubleshooting. The Help menu item did nothing
  before because it looked for an Apple Help Book the app doesn't have
- Security: range picker for the trend chart (24 Hours, 7 Days, 30 Days, 1 Year, All),
  defaulting to 7 Days. The chart stays visible with "No scans in this range" when a range is
  empty, and drops the per-run dots once there are more than 60 runs
- Security: "Fix Available" column showing how long a fixed version has been out (e.g. "5 mo"),
  from grype's `fix.available` date, with the exact day on hover. Sortable; reports from older
  grype versions without the date show "—"

#### Changed
- Work happens directly on `main`: removed the pre-commit `no-commit-to-branch` hook
- Every "install grype" hint now says `brew install --cask grype` (Settings, Help, and
  `setup.sh`, the README and the vulnerability guide); they suggested three different commands

## [App 1.0.0] - 2026-10-26

First versioned release of the SwiftUI app. App releases are tagged `app-vX.Y.Z`, separately
from the script's own versions below.

### SwiftUI App

#### Added
- App version (1.0.0) on the Dashboard's System card, in the menu bar menu and in About.
  `scripts/install-app.sh` sets the build number to the git commit count; Xcode builds show
  "development build"
- `scripts/install-app.sh` signs with the Apple Development certificate when there is one
  (stable identity, so permissions survive updates), and `--package` makes a signed zip in `dist/`
- Phase 1: native macOS menu bar + window app in `app/` with Dashboard, Installed packages,
  Runs & log viewer, and Security report views, reading `*.summary.json` and watching `~/.brew_logs`
- Phase 2: run the deployed script from the app (Update All, Dry Run, upgrade selected packages)
  with live output, a Stop button that cancels cleanly, and a confirmation before any change
- Phase 2: pin/unpin formulae and add/remove exclusions in `~/.brew_update_config` from the
  Installed view (multi-select and right-click menu)
- Quitting while an update is running asks first and stops the run cleanly
- Phase 3: Settings window (⌘,). The Schedule tab turns scheduled runs on/off and sets
  daily/weekly/monthly timing and run flags, rewriting the LaunchAgent plist (with a backup)
  and reloading it. The Updates tab edits `~/.brew_update_config` (defaults, backup and log
  retention, notifications, security scan, exclusions), rewriting only changed keys
- Phase 4: the menu bar icon warns when the last run failed, the Dock icon shows the update
  count, and the count refreshes after scheduled runs and hourly
- Phase 4: Backups screen comparing each Brewfile backup with what's installed now or with
  the previous backup, and reinstalling missing taps, formulae and casks while holding the
  run lock
- Phase 4: `brewupdates://` links (from notifications or `open`) jump to a run or section
- Doctor screen: parses every run's `*.doctor.log` into issues with a plain-language
  explanation, affected packages/taps, and suggested fixes (the app's own plus the commands
  brew doctor prints, each with a Copy button). Tracks issues across runs (first seen, how
  often, fixed recently), charts the issue count, and has **Check Now** (⇧⌘D) to run
  `brew doctor` read-only and confirm a fix. Sidebar badge and dashboard card show open issues
- Security trend chart spans a fixed 7 days with a label per day, and includes runs from
  before run summaries existed (counted from their `*.security.log` the same way the script does)
- Uninstall formulae and casks from the Installed view (right-click, inspector, or the Delete
  key). It asks first, warns when another installed formula still needs a package, and runs
  `brew uninstall` with live output while holding the run lock
- Installed view checks each cask's app on disk: self-updating casks show the app's real
  version instead of Homebrew's stale record (with "Update pending" if the app is behind),
  and casks whose app was deleted show "App missing"
- Installed inspector shows each formula's dependencies: what it needs, what needs it, and
  (for dependencies) which top-level packages it was installed for, with links to each. Flags
  dependencies nothing needs any more, using the same rule as `brew autoremove`
- Doctor flags installed casks Homebrew can no longer read (e.g. a tap using a removed cask
  DSL), which brew silently leaves out of `brew outdated` and the Installed view, with
  Homebrew's error and a link to the tap for reporting it
- Doctor flags casks whose app is missing (brew doctor doesn't check this), with
  **Clear Record** buttons that run `brew uninstall` for them
- Uninstalls and restores that need the administrator password now ask with the macOS
  password dialog (`Resources/brew-askpass.sh` via `SUDO_ASKPASS`) instead of failing
- Security hides findings for formulae uninstalled since the scan (with a note naming them and
  a "Show them" link), and **Scan Now** (⇧⌘S) runs the script's grype scan on demand
- `scripts/install-app.sh` builds the app (Release) into `/Applications` and adds a Desktop alias
- App icon: a beer mug with an upgrade badge, drawn in `app/Icon/AppIcon.svg` and rendered
  into `Assets.xcassets/AppIcon` by `app/Icon/make-icon.sh` (sips)

#### Fixed
- Runs started from the app, and the app's own `brew` calls, used a shorter PATH than the
  LaunchAgent, so Brewfile backups from app runs left out VS Code extensions

## [2.3.0] - 2026-10-25

### Added
- Clicking a notification opens that run in the Brew Updates app (`brewupdates://run/<RUN_ID>`)
  when the app has recorded its location in `~/.brew_logs/.brew-updates-app`; otherwise it
  still opens the log folder

## [2.2.1] - 2026-10-25

### Fixed
- Runs failed with exit code 141 after the security scan when it found many vulnerabilities:
  piping the report into `head` killed the upstream `grep` with SIGPIPE, and `pipefail` +
  `set -e` aborted the run before cleanup. Scheduled runs had been failing this way
  (38 times in `launchagent.log`). The report is now filtered with `awk`, which reads all input
- A security scan that found no vulnerabilities would have failed the run (exit 1), because
  `grep` exits 1 on no match under `pipefail`. The count now uses `awk` as well

## [2.2.0] - 2026-10-25

### UI Groundwork (Phase 0)

Prepares the CLI to be driven by a SwiftUI app while keeping the scheduled LaunchAgent run
as the source of truth.

### Added
- Machine-readable run summary `brew_update_<RUN_ID>.summary.json`, documented in `docs/run-summary-schema.md`
- Run lock (`~/.brew_logs/.brew-updates.lock/`) so manual and scheduled runs never overlap; exit code `5` when a run is already in progress
- `--packages LIST` to upgrade selected packages only
- `--no-color` flag and `NO_COLOR` environment variable support
- `--version` flag and `SCRIPT_VERSION`
- `BREW_UPDATE_TRIGGER` env var; runs started by the LaunchAgent are recorded as `scheduled`
- SIGINT/SIGTERM handling: cancelled runs release the lock and record `status: cancelled`
- `scripts/setup.sh --reset-launchagent`

### Changed
- Upgrades use explicit package names. Pinned and excluded packages are reported as skipped
- Upgrade results are confirmed by re-checking `brew outdated`, and logs show `name (old) → new`
- All files from a run share one `RUN_ID`
- `scripts/setup.sh` keeps an existing LaunchAgent plist, so the schedule survives re-deploys, and uses `launchctl bootout`/`bootstrap`
- `SKIP_CASKS_BY_DEFAULT` and `CLEANUP_BY_DEFAULT` now take effect

### Removed
- Retired config keys `AUTO_UPGRADE`, `LOG_LEVEL` and `BACKUP_RETENTION_DAYS`, which never had any effect. They are ignored if present

### Fixed
- `EXCLUDED_FORMULAE` / `EXCLUDED_CASKS` were only hidden from the output. `brew upgrade` still upgraded the excluded packages
- Exclusions matched by prefix (excluding `node` also hid `node@20`)
- A failed `brew update` was treated as success: `run_with_retry` always returned 0 and never retried, and `main` exited 0
- Partial upgrade failures were reported with exit code 0
- `.security.json` reports were never deleted by log retention
- Log cleanup ran before the config was loaded, so `LOG_RETENTION_DAYS` was ignored
- Config values with quotes or inline comments (as in the example config) failed validation
- `BREW_UPDATE_TIMEOUT` / `BREW_UPDATE_MAX_RETRIES` crashed the script (they reassigned readonly variables)
- `scripts/setup.sh` reset the schedule to 3:00 AM on every deploy (the template path did not exist)

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

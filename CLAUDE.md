# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is the **Homebrew Update Assistant** - a production-ready bash script that automates Homebrew package management on macOS and Linux. The script provides enterprise-grade security, intelligent error handling, and an enhanced user experience.

### Core Architecture

- **Single File Design**: `brew-updates.command` - Complete standalone bash script (~1,600 lines)
- **Bash 3.2 Compatible**: The LaunchAgent runs it with macOS `/bin/bash` 3.2, so no associative arrays or `mapfile`, and guard empty array expansions under `set -u`
- **UI Contract**: Each run writes `~/.brew_logs/brew_update_<RUN_ID>.summary.json` for the SwiftUI app. See [docs/run-summary-schema.md](docs/run-summary-schema.md); bump `SUMMARY_SCHEMA_VERSION` on breaking changes
- **Run Lock**: `~/.brew_logs/.brew-updates.lock/` prevents overlapping runs (exit code 5)
- **Configuration System**: Optional `~/.brew_update_config` for user customization
- **Logging & Backups**: Automatic file management in `~/.brew_logs/` and `~/.brew_backups/`
- **Terminal Integration**: Smart detection and clickable links for supported terminals

### Key Features

- **Security-First**: Input validation, no eval usage, safe command execution
- **Intelligent Retry**: Exponential backoff for network operations
- **Configuration Support**: File-based and environment variable configuration
- **Terminal Awareness**: Clickable links in iTerm2, VS Code terminal, etc.
- **Package Exclusion**: Support for excluding specific formulae/casks from updates

## Development Commands

### Deployment Process

**CRITICAL**: This project has TWO locations:
- **Source/Development**: `~/Documents/my-projects/scripts/brewUpdates/` (edit here)
- **Production/Execution**: `~/bin/` (LaunchAgent runs from here)

**After making ANY changes to `brew-updates.command`, you MUST deploy:**

```bash
cd ~/Documents/my-projects/scripts/brewUpdates
./scripts/setup.sh
```

The `scripts/setup.sh` script will:
- Copy updated script to `~/bin/`
- Keep an existing LaunchAgent plist so a custom schedule survives (`--reset-launchagent` regenerates the default)
- Reload the LaunchAgent (`launchctl bootout` + `bootstrap`)
- Verify checksums match
- Create backups of old versions

**NEVER edit `~/bin/brew-updates.command` directly** - always edit the source and deploy.

See [DEPLOYMENT.md](DEPLOYMENT.md) for full deployment workflow.

### Testing
```bash
# Test without making changes (recommended for development)
./brew-updates.command --dry-run --verbose

# Test specific functionality
./brew-updates.command --help
./brew-updates.command --skip-casks --dry-run
./brew-updates.command --yes --verbose  # Automation mode

# Test error handling (simulate network issues, etc.)
export BREW_UPDATE_TIMEOUT=5  # Short timeout for testing
./brew-updates.command --dry-run

# Test the deployed version
~/bin/brew-updates.command --dry-run --verbose

# Verify source and deployed versions match
md5 ~/Documents/my-projects/scripts/brewUpdates/brew-updates.command ~/bin/brew-updates.command
```

### Code Validation
```bash
# Check bash syntax
bash -n brew-updates.command

# Use shellcheck if available (brew install shellcheck)
shellcheck brew-updates.command

# After validation, deploy changes
./scripts/setup.sh
```

## SwiftUI App (`app/`)

- Native macOS app (menu bar + window), Swift 6, macOS 15+. Phases 1–4 done (viewing; run/dry run/upgrade selected with live output, pin and exclude; Settings window; menu bar/Dock status, backup compare/restore, notification links)
- The Xcode project is **generated** by XcodeGen from `app/project.yml` and is gitignored. Run `cd app && xcodegen generate` after adding/removing files; never change settings in Xcode's project editor
- Layout: `Models/` (pure parsing, no UI) → `Services/` (files, `brew`, `launchctl`) → `AppModel.swift` (`@Observable`, `@MainActor`) → `Views/`
- The app must only ever invoke the **deployed** `~/bin/brew-updates.command`, read run data via `*.summary.json` (docs/run-summary-schema.md), and check `SystemStatus.minimumScriptVersion`
- All `brew` calls set `HOMEBREW_NO_AUTO_UPDATE=1`, so the only state changes are explicit user actions (pin/unpin). Updates and upgrades always go through the script (`ScriptRunner`, with `--yes --no-color` and `BREW_UPDATE_TRIGGER=app`)
- Stopping a run sends SIGINT to the script and its children (like Ctrl-C), so it still writes a `cancelled` summary and releases the lock
- Exclusions are written to `~/.brew_update_config` by `ConfigEditor`, which only rewrites the `EXCLUDED_*` line and keeps comments. Names must match the script's regex or it drops the whole list
- Schedule edits go through `LaunchAgentService`: rewrite the plist (backup `<plist>.app-backup`), then `launchctl bootout` + `bootstrap`. Never reload while the run lock is held, because bootout stops a scheduled run in progress. On/off uses `launchctl enable`/`disable` so it survives logins. Tests must never call launchctl against the real `com.user.brew-update` label
- Every brew/script call from the app uses `BrewService.searchPath`, the same PATH the LaunchAgent sets. `brew bundle dump` silently drops VS Code extensions when `code` (in /usr/local/bin) isn't on PATH
- Restores (`brew bundle install --no-upgrade` of the missing taps/formulae/casks) and uninstalls hold the script's run lock via `RunLock`, which follows the script's `acquire_lock` protocol (`AppModel+Packages.swift`, `runLiveHoldingLock`)
- Casks: `CaskAppLocator` finds each cask's app (current `app`/`uninstall delete` artifacts plus the Caskroom `INSTALL_RECEIPT.json`, which keeps pre-rename names) in /Applications and ~/Applications. `auto_updates` casks show the app's own version; brew's record goes stale because `brew outdated` and the script skip them. Never count them as outdated
- Security: scans are snapshots, so the view hides findings for formulae no longer installed (`Vulnerability.partition`). **Scan Now** (`SecurityScanner`) runs the script's grype command as JSON, keeps the result in memory only, and is disabled while a run is in progress. It isn't added to the trend chart, whose counts come from the script's table report
- Password prompts: uninstalls and restores set `SUDO_ASKPASS` to the bundled `Resources/brew-askpass.sh` (an osascript password dialog; brew keeps that variable and runs `sudo -A`). The script prints the password only to sudo; never log it, write it anywhere, or use askpass for script runs
- Doctor shows the app's own checks (`AppModel.appDoctorIssues`, e.g. `DoctorIssue.missingCaskApps`) next to the newest brew doctor report only; they aren't part of the logged history
- Dependencies: `PackageDependencies` works them out from `brew info`'s `runtime_dependencies` (recursive, with `declared_directly`), so no extra brew calls. "Leftover" must match `brew autoremove`: nothing installed lists the formula at all, directly or indirectly (old receipts can still list e.g. `icu4c@78`)
- Uninstall (Installed view, Doctor's Clear Record) goes through `UninstallPlan`: full names, `--formula`/`--cask` when the selection is one kind, a warning for packages other installed formulae need (from `runtime_dependencies`). Never pass `--ignore-dependencies` or `--zap`
- `brewupdates://run/<RUN_ID>` and `brewupdates://<section>` links are parsed by `AppLink`. The script uses them in notifications only when `~/.brew_logs/.brew-updates-app` (written by the app) points at an existing app
- Tests (Swift Testing) compile `Models/` and `Services/` directly into an unhosted test bundle. Hosted tests hang because a menu bar app never quits
- Build/test from the terminal with the default DerivedData (`~/Library/Developer`). A `-derivedDataPath` inside `~/Documents` makes `xctest` block on a Documents permission prompt:
  ```bash
  cd app && xcodebuild -project BrewUpdates.xcodeproj -scheme BrewUpdates -destination 'platform=macOS,arch=arm64' test
  ```
- Lint: `swiftlint lint --strict` (config `app/.swiftlint.yml`), enforced by the pre-commit hook `hooks/swiftlint.sh`
- Doctor screen: `DoctorReport` parses `*.doctor.log` text (`brew doctor --json` exists but is hidden from `--help`, so not relied on). `DoctorCheck` recognises warnings by headline fragments taken from Homebrew's `Library/Homebrew/diagnostic.rb`; add advice there plus a test when a new warning shows up. **Check Now** runs `brew doctor --verbose` (read-only) and keeps the result in memory only, never in `~/.brew_logs`. Fixes are copy-to-clipboard; the app does not run them
- Installed copy: `scripts/install-app.sh` builds Release into `/Applications/Brew Updates.app` (+ Desktop alias). It refuses to run while that copy is open. Re-run it after app changes the user wants in their everyday copy
- App icon: edit `app/Icon/AppIcon.svg`, then run `app/Icon/make-icon.sh` (sips renders every size into `Assets.xcassets/AppIcon.appiconset`). Don't edit the PNGs directly
- The user is learning SwiftUI and Xcode: explain new SwiftUI concepts briefly in code comments and keep `app/GUIDE.md` current

## Code Structure

### Main Functions Flow
1. `main()` - Entry point, orchestrates entire process
2. `parse_arguments()` - CLI argument handling with validation
3. `load_config()` - Configuration file processing
4. `update_homebrew()` - Core Homebrew update logic
5. `check_outdated_packages()` - Package discovery and filtering
6. `upgrade_packages()` - Package upgrade execution
7. `run_doctor()` - Health check with intelligent output parsing
8. `cleanup_homebrew()` - Cleanup and maintenance

### Security Architecture
- **Input Validation**: `validate_input()` with regex patterns
- **Safe Execution**: `run_with_timeout()` and `run_with_retry()` functions
- **Path Sanitization**: All file paths validated before use
- **No Eval Usage**: Commands executed as arrays, not strings

### Error Handling
- **Exit Codes**: Specific codes for different error types
  - `0`: Success
  - `1`: General error
  - `2`: Network error
  - `3`: Disk space error
  - `4`: Homebrew error
  - `5`: Another run is already in progress
- **Capturing exit codes**: Use `cmd || rc=$?`, never `if ! cmd; then rc=$?` (inside that branch `$?` is always 0)
- **Retry Logic**: Exponential backoff with configurable max retries
- **Graceful Degradation**: Continue operation when non-critical components fail

## Configuration System

### Environment Variables
- `BREW_UPDATE_TIMEOUT`: Command timeout (default: 300s)
- `BREW_UPDATE_MAX_RETRIES`: Retry attempts (default: 3)
- `BREW_UPDATE_TRIGGER`: Label for the run summary's `trigger` field (e.g. `app`)
- `NO_COLOR`: Disable colored output (same as `--no-color`)

### Config File Format
The `~/.brew_update_config` file uses key=value format with validation:
- `MAX_BACKUP_COUNT`: Number of Brewfile backups to keep
- `LOG_RETENTION_DAYS`: Delete per-run files older than this
- `EXCLUDED_FORMULAE`: Space-separated package names to skip (exact match)
- `EXCLUDED_CASKS`: Space-separated cask names to skip (exact match)
- `SKIP_CASKS_BY_DEFAULT` / `CLEANUP_BY_DEFAULT`: Run defaults
- `SECURITY_SCAN_ENABLED`, `SECURITY_SCAN_SEVERITY`, `ENABLE_NOTIFICATIONS`
- Values may be quoted and may carry a trailing ` # comment`
- Retired (ignored): `AUTO_UPGRADE`, `LOG_LEVEL`, `BACKUP_RETENTION_DAYS`

## Important Implementation Notes

### Security Considerations
- Never use `eval` or similar dangerous constructs
- All user inputs must be validated with regex patterns
- File paths must be sanitized to prevent directory traversal
- Commands should be executed as arrays, not concatenated strings

### Terminal Integration
- The script detects terminal capabilities for clickable links
- `create_clickable_link()` handles different terminal types (iTerm2, VS Code, Terminal.app)
- Color output is conditional based on terminal support

### Backup System
- Automatic Brewfile backups before operations
- Configurable retention with cleanup of old backups
- Safe file operations to prevent corruption

### Package Filtering
- Supports exclusion lists for both formulae and casks
- Uses regex patterns for filtering outdated packages
- Validates package names before processing

## Common Development Patterns

### Adding New Features
1. Add command-line option in `parse_arguments()`
2. Add validation if needed in `validate_input()`
3. Implement feature following existing patterns
4. Add verbose logging with `log_verbose()`
5. Update help text in `show_usage()`

### Error Handling Pattern
```bash
if ! some_operation; then
    log_error "Failed to perform operation"
    return $EXIT_SPECIFIC_ERROR
fi
```

### Safe Command Execution
```bash
# Good - uses array and proper error handling
if run_with_retry "brew update" "Homebrew update"; then
    log_success "Operation completed"
else
    log_error "Operation failed"
    return $EXIT_HOMEBREW_ERROR
fi
```

## Testing Strategy

### Manual Testing Scenarios
1. **Normal Operation**: Full update cycle with various flags
2. **Network Issues**: Simulate connection problems
3. **Disk Space**: Test low disk space handling
4. **Configuration**: Test various config file scenarios
5. **Terminal Types**: Test in different terminal applications

### Edge Cases to Test
- Empty/invalid configuration files
- Network connectivity issues during operations
- Homebrew command failures
- Disk space exhaustion
- Package exclusion lists with special characters

## Documentation Standards

- All functions should have clear, descriptive names
- Complex logic should include inline comments explaining the "why"
- Error messages should be actionable and user-friendly
- Log messages should be structured and searchable

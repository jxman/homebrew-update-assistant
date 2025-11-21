# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is the **Homebrew Update Assistant** - a production-ready bash script that automates Homebrew package management on macOS and Linux. The script provides enterprise-grade security, intelligent error handling, and an enhanced user experience.

### Core Architecture

- **Single File Design**: `brew-updates.command` - Complete standalone bash script (~940 lines)
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
- Reload the LaunchAgent
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
- **Retry Logic**: Exponential backoff with configurable max retries
- **Graceful Degradation**: Continue operation when non-critical components fail

## Configuration System

### Environment Variables
- `BREW_UPDATE_TIMEOUT`: Command timeout (default: 300s)
- `BREW_UPDATE_MAX_RETRIES`: Retry attempts (default: 3)
- `BREW_UPDATE_DEBUG`: Enable debug mode

### Config File Format
The `~/.brew_update_config` file uses key=value format with validation:
- `BACKUP_RETENTION_DAYS`: Backup cleanup threshold
- `EXCLUDED_FORMULAE`: Space-separated package names to skip
- `EXCLUDED_CASKS`: Space-separated cask names to skip
- `LOG_LEVEL`: DEBUG, INFO, WARNING, ERROR

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

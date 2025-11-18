# Pre-commit Hooks Setup Guide

This project uses **pre-commit** to automatically check code quality before commits.

## 🎯 What Pre-commit Does

Pre-commit hooks run automatically before each `git commit` to:
- ✅ Check shell script syntax (bash -n)
- ✅ Run ShellCheck linting
- ✅ Validate YAML and JSON files
- ✅ Check Markdown formatting
- ✅ Detect private keys or secrets
- ✅ Ensure files are executable
- ✅ Trim trailing whitespace
- ✅ Prevent committing to main branch directly
- ✅ Block log files from being committed

## 📦 Installation

### 1. Install pre-commit

```bash
# Using pip (recommended)
pip install pre-commit

# Or using Homebrew
brew install pre-commit

# Or using pipx
pipx install pre-commit
```

### 2. Install the hooks

```bash
cd "/Users/johxan/Documents/my-projects/scripts/Brew Updates"
pre-commit install
```

You should see:
```
pre-commit installed at .git/hooks/pre-commit
```

### 3. Verify installation

```bash
pre-commit --version
```

## 🚀 Usage

### Automatic (Recommended)

Hooks run automatically when you commit:

```bash
git add file.sh
git commit -m "feat: add new feature"
# ↑ Pre-commit hooks run here automatically
```

### Manual Run

Test hooks without committing:

```bash
# Run on all files
pre-commit run --all-files

# Run on staged files only
pre-commit run

# Run specific hook
pre-commit run shellcheck --all-files
```

### Skip Hooks (When Necessary)

**Warning:** Only skip hooks if you know what you're doing!

```bash
# Skip all hooks for one commit
git commit --no-verify -m "chore: emergency fix"

# Or set environment variable
SKIP=shellcheck git commit -m "chore: skip shellcheck only"
```

## 🔧 Configuration

The configuration is in `.pre-commit-config.yaml`. Here's what each hook does:

### Shell Script Validation

**ShellCheck** (shellcheck-py)
- Lints shell scripts for common mistakes
- Severity: warning
- Excludes: `.git/`, `.github/`

**Bash Syntax Check** (local)
- Validates bash syntax with `bash -n`
- Runs on: `*.sh`, `*.command`, `*.bash`

### File Checks

**check-added-large-files**
- Prevents files >500KB from being committed
- Protects repo from accidental large file commits

**check-case-conflict**
- Prevents filename conflicts on case-insensitive filesystems

**end-of-file-fixer**
- Ensures files end with newline
- Excludes: `*.log`, `*.json`

**trailing-whitespace**
- Removes trailing whitespace
- Preserves markdown line breaks

**check-yaml/check-json**
- Validates YAML and JSON syntax

**detect-private-key**
- Scans for accidentally committed private keys

**check-merge-conflict**
- Detects merge conflict markers

**no-commit-to-branch**
- Prevents direct commits to `main`/`master`
- Forces use of feature branches

### Custom Hooks

**check-script-executable** (hooks/check-executable.sh)
- Ensures `.command` and `.sh` files are executable
- Auto-fixes: `chmod +x file.sh`

**no-log-files**
- Blocks log files from being committed
- Prevents bloating the repo

**check-todos**
- Warns about unresolved TODO/FIXME comments
- Helps track technical debt

## 🐛 Troubleshooting

### Hook fails with "command not found"

Install the missing tool:

```bash
# ShellCheck
brew install shellcheck

# markdownlint
npm install -g markdownlint-cli
```

### Hook fails on existing files

Run hooks on all files to fix issues:

```bash
pre-commit run --all-files
```

### Update hooks to latest versions

```bash
pre-commit autoupdate
```

### Clean and reinstall

```bash
pre-commit clean
pre-commit uninstall
pre-commit install
```

## 📋 Common Fixes

### ShellCheck Warnings

```bash
# Run ShellCheck with explanation
shellcheck -x brew-updates.command

# Auto-fix some issues
shellcheck -f diff brew-updates.command | git apply
```

### Markdown Linting

```bash
# Fix markdown issues automatically
markdownlint --fix README.md

# Ignore specific rules in file
<!-- markdownlint-disable MD013 -->
Long line that would normally fail...
<!-- markdownlint-enable MD013 -->
```

### Script Not Executable

```bash
# Make script executable
chmod +x brew-updates.command

# Verify
ls -l brew-updates.command
```

## 🎓 Best Practices

### 1. Run hooks before pushing

```bash
# Test everything before push
pre-commit run --all-files
git push origin feature-branch
```

### 2. Keep hooks updated

```bash
# Monthly update
pre-commit autoupdate
git add .pre-commit-config.yaml
git commit -m "chore: update pre-commit hooks"
```

### 3. Use feature branches

```bash
# Create feature branch (hooks won't block)
git checkout -b feature/new-security-scan
# Make changes
git commit -m "feat: add new feature"
git push origin feature/new-security-scan
# Create PR to main
```

### 4. Fix issues incrementally

Don't skip hooks! Fix issues as they're found:

```bash
# Hook fails? Fix the issue:
shellcheck brew-updates.command  # See what's wrong
# Fix the code
git add brew-updates.command
git commit -m "fix: address shellcheck warnings"
```

## 🔗 Useful Links

- [Pre-commit documentation](https://pre-commit.com/)
- [ShellCheck wiki](https://www.shellcheck.net/wiki/)
- [Markdownlint rules](https://github.com/DavidAnson/markdownlint/blob/main/doc/Rules.md)

## ⚙️ CI/CD Integration

Pre-commit hooks also run in GitHub Actions:

```yaml
# .github/workflows/test.yml already has:
- ShellCheck validation
- Bash syntax checking
- Documentation checks
```

This ensures the same checks run locally and in CI/CD!

## 📝 Adding New Hooks

To add a new hook:

1. Edit `.pre-commit-config.yaml`
2. Add the hook configuration
3. Update this documentation
4. Run `pre-commit run --all-files` to test

Example:

```yaml
  - repo: https://github.com/example/tool
    rev: v1.0.0
    hooks:
      - id: my-new-hook
        name: My new validation
        args: ['--fix']
```

## 🚫 Disabling Specific Hooks

Add to `.pre-commit-config.yaml`:

```yaml
  - repo: https://github.com/shellcheck-py/shellcheck-py
    rev: v0.10.0.1
    hooks:
      - id: shellcheck
        exclude: ^scripts/legacy/  # Skip legacy scripts
```

Or create `.shellcheckrc`:

```bash
# Disable specific rules globally
disable=SC2034,SC2086
```

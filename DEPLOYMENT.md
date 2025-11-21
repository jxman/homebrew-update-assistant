# Deployment Guide

This document explains how to deploy and update the Homebrew Update Assistant.

## Overview

The project has two important locations:

1. **Development/Source**: `~/Documents/my-projects/scripts/brewUpdates/`
   - Where you edit and update the script
   - Where the git repository lives
   - Contains `brew-updates.command`, `setup.sh`, and configuration

2. **Production/Execution**: `~/bin/`
   - Where the LaunchAgent runs the script from
   - Contains the deployed copy of `brew-updates.command`
   - This is what executes daily at 3:00 AM

## Initial Setup

When setting up for the first time:

```bash
cd ~/Documents/my-projects/scripts/brewUpdates
./scripts/setup.sh
```

This will:
- ✅ Copy `brew-updates.command` to `~/bin/`
- ✅ Install the LaunchAgent configuration
- ✅ Create necessary directories (`~/.brew_logs`, `~/.brew_backups`)
- ✅ Create a sample config file (`~/.brew_update_config`)
- ✅ Verify all dependencies

## Updating the Script

**Whenever you edit `brew-updates.command` in the project directory:**

### Option 1: Run setup.sh (Recommended)

```bash
cd ~/Documents/my-projects/scripts/brewUpdates
./scripts/setup.sh
```

This is the safest method because it:
- Backs up the current `~/bin/brew-updates.command`
- Verifies the copy with MD5 checksum
- Reloads the LaunchAgent if needed
- Shows you a summary of what changed

### Option 2: Manual copy

```bash
cp ~/Documents/my-projects/scripts/brewUpdates/brew-updates.command ~/bin/
chmod +x ~/bin/brew-updates.command
```

Then verify the copy:
```bash
md5 ~/Documents/my-projects/scripts/brewUpdates/brew-updates.command ~/bin/brew-updates.command
```

Both should show the same MD5 hash.

## Testing Changes

### Before Deploying (Dry Run)

Test in the development directory without making changes:

```bash
cd ~/Documents/my-projects/scripts/brewUpdates
./brew-updates.command --dry-run --verbose
```

### After Deploying (Production Test)

Test the deployed version:

```bash
~/bin/brew-updates.command --dry-run --verbose
```

Or run a real update:

```bash
~/bin/brew-updates.command --yes --verbose
```

### Test LaunchAgent

Manually trigger the LaunchAgent to test the scheduled job:

```bash
launchctl start com.user.brew-update
```

Watch the logs in real-time:

```bash
tail -f ~/.brew_logs/launchagent.log
```

## Deployment Workflow

**Recommended workflow for making changes:**

1. **Edit** the script in the project directory:
   ```bash
   code ~/Documents/my-projects/scripts/brewUpdates/brew-updates.command
   ```

2. **Test** locally with dry-run:
   ```bash
   cd ~/Documents/my-projects/scripts/brewUpdates
   ./brew-updates.command --dry-run --verbose
   ```

3. **Deploy** to production:
   ```bash
   ./scripts/setup.sh
   ```

4. **Verify** the deployment:
   ```bash
   md5 ~/Documents/my-projects/scripts/brewUpdates/brew-updates.command ~/bin/brew-updates.command
   ```

5. **Test** the deployed version:
   ```bash
   ~/bin/brew-updates.command --dry-run --verbose
   ```

6. **Commit** your changes to git:
   ```bash
   git add brew-updates.command
   git commit -m "feat: description of your changes"
   git push
   ```

## LaunchAgent Management

### Check if LaunchAgent is running

```bash
launchctl list | grep brew-update
```

Output example:
```
PID    Status  Label
-      0       com.user.brew-update
```

### View LaunchAgent schedule

```bash
cat ~/Library/LaunchAgents/com.user.brew-update.plist
```

### Manually trigger a run

```bash
launchctl start com.user.brew-update
```

### Disable LaunchAgent

```bash
launchctl unload ~/Library/LaunchAgents/com.user.brew-update.plist
```

### Re-enable LaunchAgent

```bash
launchctl load ~/Library/LaunchAgents/com.user.brew-update.plist
```

### Update LaunchAgent configuration

After editing `com.user.brew-update.plist`:

```bash
launchctl unload ~/Library/LaunchAgents/com.user.brew-update.plist
launchctl load ~/Library/LaunchAgents/com.user.brew-update.plist
```

Or just run:
```bash
./scripts/setup.sh
```

## Uninstalling

### Complete Uninstall (Remove Everything)

Remove the script, LaunchAgent, and all data files:

```bash
cd ~/Documents/my-projects/scripts/brewUpdates
./scripts/setup.sh --uninstall --all
```

Or use the uninstall script directly:

```bash
./scripts/uninstall.sh --all
```

This removes:
- ✓ Installed script (`~/bin/brew-updates.command`)
- ✓ LaunchAgent configuration
- ✓ Log files (`~/.brew_logs/`)
- ✓ Backup files (`~/.brew_backups/`)
- ✓ Configuration file (`~/.brew_update_config`)

### Partial Uninstall (Keep Data)

Remove only the script and LaunchAgent, preserving your logs, backups, and config:

```bash
./scripts/uninstall.sh
```

This preserves your data while removing the active installation.

### Selective Uninstall

Remove specific components:

```bash
# Remove script/LaunchAgent and logs only (keep backups and config)
./scripts/uninstall.sh --logs

# Remove script/LaunchAgent and backups only
./scripts/uninstall.sh --backups

# Remove script/LaunchAgent and config only
./scripts/uninstall.sh --config

# Remove logs and backups (keep config)
./scripts/uninstall.sh --logs --backups
```

### Dry Run (Preview)

See what would be removed without actually removing it:

```bash
./scripts/uninstall.sh --dry-run --all
```

### Uninstall Options

| Option | Description |
|--------|-------------|
| `--logs` | Remove log directory (`~/.brew_logs`) |
| `--backups` | Remove backup directory (`~/.brew_backups`) |
| `--config` | Remove config file (`~/.brew_update_config`) |
| `--all` | Remove everything (script, LaunchAgent, and all data) |
| `--dry-run` | Preview what would be removed |
| `--force` | Skip confirmation prompts |
| `-h, --help` | Show help message |

### Reinstalling After Uninstall

To reinstall after uninstalling:

```bash
cd ~/Documents/my-projects/scripts/brewUpdates
./scripts/setup.sh
```

Your previous config will be restored if you didn't use `--config` during uninstall.

## File Locations

### Source Files (Development)
```
~/Documents/my-projects/scripts/brewUpdates/
├── brew-updates.command          # Main script (edit here)
├── scripts/                       # Management scripts
│   ├── setup.sh                   # Deployment script
│   ├── uninstall.sh               # Uninstall script
│   └── fix-vulnerabilities.sh     # Utility script
├── com.user.brew-update.plist     # LaunchAgent template
├── README.md                      # User documentation
├── DEPLOYMENT.md                  # This file
└── CLAUDE.md                      # Claude Code instructions
```

### Deployed Files (Production)
```
~/bin/
└── brew-updates.command           # Deployed script (DO NOT EDIT)

~/Library/LaunchAgents/
└── com.user.brew-update.plist     # Active LaunchAgent config

~/.brew_logs/
├── brew_update_YYYYMMDD_HHMMSS.log           # Main logs
├── brew_update_YYYYMMDD_HHMMSS.upgrades.log  # Upgrade details
├── brew_update_YYYYMMDD_HHMMSS.security.log  # Security scan
├── brew_update_YYYYMMDD_HHMMSS.doctor.log    # Health check
├── launchagent.log                            # LaunchAgent stdout
└── launchagent_error.log                      # LaunchAgent stderr

~/.brew_backups/
└── brew_backup_YYYYMMDD_HHMMSS    # Brewfile backups

~/.brew_update_config              # User configuration
```

## Troubleshooting

### Script versions don't match

**Problem**: Running `~/bin/brew-updates.command` shows old behavior

**Solution**:
```bash
cd ~/Documents/my-projects/scripts/brewUpdates
./scripts/setup.sh
```

### LaunchAgent not running

**Problem**: Script doesn't run at 3:00 AM

**Check**:
```bash
launchctl list | grep brew-update
```

**Fix**:
```bash
launchctl load ~/Library/LaunchAgents/com.user.brew-update.plist
```

### Permission denied

**Problem**: `./scripts/setup.sh` or `./brew-updates.command` gives permission error

**Fix**:
```bash
chmod +x ~/Documents/my-projects/scripts/brewUpdates/scripts/setup.sh
chmod +x ~/Documents/my-projects/scripts/brewUpdates/scripts/uninstall.sh
chmod +x ~/Documents/my-projects/scripts/brewUpdates/brew-updates.command
```

### Logs not showing updates

**Problem**: LaunchAgent runs but logs are empty or incomplete

**Check**:
1. Verify script version matches:
   ```bash
   md5 ~/Documents/my-projects/scripts/brewUpdates/brew-updates.command ~/bin/brew-updates.command
   ```

2. Check LaunchAgent is using correct path:
   ```bash
   grep ProgramArguments ~/Library/LaunchAgents/com.user.brew-update.plist -A 5
   ```

3. Manually test the deployed script:
   ```bash
   ~/bin/brew-updates.command --yes --verbose
   ```

## Best Practices

1. **Always use setup.sh after editing the script** - Don't manually copy files
2. **Test with --dry-run first** - Verify changes before running for real
3. **Check MD5 checksums** - Ensure source and deployed versions match
4. **Review logs after LaunchAgent runs** - Verify everything worked
5. **Keep the project in version control** - Git tracks your changes
6. **Document changes in commits** - Use clear commit messages
7. **Never edit ~/bin/brew-updates.command directly** - Always edit the source

## Quick Reference

| Task | Command |
|------|---------|
| Deploy script | `cd ~/Documents/my-projects/scripts/brewUpdates && ./scripts/setup.sh` |
| Test locally | `./brew-updates.command --dry-run --verbose` |
| Test deployed | `~/bin/brew-updates.command --dry-run --verbose` |
| Verify checksums | `md5 ~/Documents/my-projects/scripts/brewUpdates/brew-updates.command ~/bin/brew-updates.command` |
| Check LaunchAgent | `launchctl list \| grep brew-update` |
| Trigger now | `launchctl start com.user.brew-update` |
| View logs | `tail -f ~/.brew_logs/launchagent.log` |
| Edit config | `nano ~/.brew_update_config` |
| Uninstall (keep data) | `./scripts/uninstall.sh` |
| Uninstall (remove all) | `./scripts/setup.sh --uninstall --all` |
| Preview uninstall | `./scripts/uninstall.sh --dry-run --all` |

## Automation Options

### Option 1: Git Hook (Recommended)

Create `.git/hooks/post-merge` to auto-deploy after git pull:

```bash
#!/bin/bash
cd ~/Documents/my-projects/scripts/brewUpdates
./scripts/setup.sh
```

### Option 2: Watch Script

Use `fswatch` to auto-deploy on file changes:

```bash
brew install fswatch
fswatch -o ~/Documents/my-projects/scripts/brewUpdates/brew-updates.command | \
  xargs -n1 -I{} ~/Documents/my-projects/scripts/brewUpdates/scripts/setup.sh
```

### Option 3: Alias

Add to your `~/.zshrc` or `~/.bashrc`:

```bash
alias deploy-brew='cd ~/Documents/my-projects/scripts/brewUpdates && ./scripts/setup.sh'
```

Then just run:
```bash
deploy-brew
```

## See Also

- [README.md](README.md) - User documentation
- [CLAUDE.md](CLAUDE.md) - Development guidelines
- [CHANGELOG.md](CHANGELOG.md) - Version history

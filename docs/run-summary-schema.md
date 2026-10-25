# Run Summary Schema

Every run of `brew-updates.command` that gets past the run lock writes a machine-readable
summary next to its logs:

```text
~/.brew_logs/brew_update_<RUN_ID>.summary.json
```

This file is the contract between the CLI and the SwiftUI app. The app should read it
instead of parsing the human-readable logs.

## Guarantees

- **Written for every run that holds the lock**, including failed and cancelled runs. It is
  written from the script's `EXIT` trap.
- **Atomic**: written to `*.summary.json.tmp` and renamed, so readers never see a partial file.
- **Not written** for `--help` or `--version`, or when another run already holds the lock
  (exit code `5`).
- **Shared run ID**: every file from one run (`.log`, `.upgrades.log`, `.doctor.log`,
  `.security.*`, `.summary.json`) and the Brewfile backup use the same `RUN_ID`
  (`YYYYMMDD_HHMMSS`, local time).
- **Retention**: summaries are deleted with the other per-run files after
  `LOG_RETENTION_DAYS`.

## Versioning

- `schema_version` (integer) is bumped on any **breaking** change, such as a removed or
  renamed field or a changed type.
- Adding fields is not a breaking change, so consumers must ignore unknown fields.
- `script_version` is the script's semantic version (`brew-updates.command --version`).
  The app should check it against a minimum version and ask the user to run
  `scripts/setup.sh` when the deployed script is too old.

## Fields (schema_version 1)

| Field | Type | Description |
|-------|------|-------------|
| `schema_version` | int | Summary format version (currently `1`) |
| `script_version` | string | Script version, e.g. `"2.2.0"` |
| `run_id` | string | `YYYYMMDD_HHMMSS` shared by all files of this run |
| `trigger` | string | `scheduled` (LaunchAgent), `manual`, or the value of `BREW_UPDATE_TRIGGER` (e.g. `app`) |
| `started_at` / `finished_at` | string | ISO 8601 UTC, e.g. `"2026-10-25T07:01:15Z"` |
| `duration_seconds` | int | Wall-clock duration |
| `status` | string | See [Status values](#status-values) |
| `exit_code` | int | Process exit code (see [Exit codes](#exit-codes)) |
| `dry_run` | bool | `--dry-run` was used |
| `options.skip_casks` | bool | Casks skipped (flag or `SKIP_CASKS_BY_DEFAULT`) |
| `options.skip_cleanup` | bool | Cleanup skipped (flag or `CLEANUP_BY_DEFAULT=false`) |
| `options.skip_security_scan` | bool | `--skip-security-scan` was used |
| `options.packages` | string[] | Names passed with `--packages` (empty means all outdated packages) |
| `homebrew_version` | string | First line of `brew --version` (empty if the run failed earlier) |
| `outdated.formulae` / `outdated.casks` | Package[] | Outdated packages selected for upgrade, after exclusions, pins and `--packages` |
| `upgraded.formulae` / `upgraded.casks` | Package[] | Packages confirmed upgraded (no longer outdated afterwards) |
| `failed.formulae` / `failed.casks` | string[] | Packages attempted but still outdated afterwards |
| `skipped.excluded` | string[] | Outdated but excluded by `EXCLUDED_FORMULAE` / `EXCLUDED_CASKS` |
| `skipped.pinned` | string[] | Outdated but pinned (`brew pin`) |
| `skipped.not_outdated` | string[] | Requested with `--packages` but not outdated or not installed |
| `backup.created` | bool | Brewfile backup succeeded |
| `backup.path` | string \| null | Backup file, or `null` if missing or already rotated out |
| `doctor.status` | string | `ok`, `warnings`, `errors`, `not_run` |
| `security.status` | string | `completed`, `skipped`, `disabled`, `unavailable` (no grype), `dry_run`, `failed`, `not_run` |
| `security.vulnerability_count` | int | Findings with fixes available (Critical/High/Medium) |
| `cleanup.status` | string | `completed`, `issues`, `skipped`, `dry_run`, `not_run` |
| `files.*` | string \| null | Absolute paths of `log`, `upgrades_log`, `doctor_log`, `security_log`, `security_detailed_log`, `security_json`, or `null` if that file was not produced |

`Package` is `{"name": string, "from": string, "to": string}`. `from` is the installed
version or versions as Homebrew reports them (for example `"1.0, 1.1"`), and `to` is the
available version.

In a dry run, `outdated` lists what would be upgraded and `upgraded` and `failed` are empty.

### Status values

| `status` | Meaning |
|----------|---------|
| `success` | Run completed, exit code 0, and no package failed to upgrade |
| `partial` | Run completed, but at least one upgrade failed or the exit code is non-zero |
| `failed` | Run aborted before completing (e.g. `brew update` failed, insufficient disk space) |
| `cancelled` | Run was stopped by SIGINT (130) or SIGTERM (143) |

### Exit codes

| Code | Meaning |
|------|---------|
| `0` | Success |
| `1` | General error, or some package upgrades failed |
| `2` | Network error |
| `3` | Insufficient disk space |
| `4` | Homebrew error (e.g. `brew update` failed after retries) |
| `5` | Another run is already in progress (no summary is written) |
| `130` / `143` | Interrupted / terminated |

## Run lock

Runs take a lock at `~/.brew_logs/.brew-updates.lock/`, a directory containing the holder's
`pid`. A second run exits immediately with code `5` and the message
`Another Homebrew update is already running (PID n)` on stderr. A lock whose PID is no longer
alive is treated as stale and removed. The app can check for this directory to show a
"running" state.

## Example

```json
{
  "schema_version": 1,
  "script_version": "2.2.0",
  "run_id": "20261025_030115",
  "trigger": "scheduled",
  "started_at": "2026-10-25T07:01:15Z",
  "finished_at": "2026-10-25T07:09:42Z",
  "duration_seconds": 507,
  "status": "success",
  "exit_code": 0,
  "dry_run": false,
  "options": {
    "skip_casks": false,
    "skip_cleanup": false,
    "skip_security_scan": false,
    "packages": []
  },
  "homebrew_version": "Homebrew 7.0.10",
  "outdated": {
    "formulae": [{ "name": "z3", "from": "5.3.1", "to": "5.3.2" }],
    "casks": []
  },
  "upgraded": {
    "formulae": [{ "name": "z3", "from": "5.3.1", "to": "5.3.2" }],
    "casks": []
  },
  "failed": { "formulae": [], "casks": [] },
  "skipped": { "excluded": [], "pinned": [], "not_outdated": [] },
  "backup": { "created": true, "path": "/Users/me/.brew_backups/brew_backup_20261025_030115" },
  "doctor": { "status": "warnings" },
  "security": { "status": "completed", "vulnerability_count": 3 },
  "cleanup": { "status": "completed" },
  "files": {
    "log": "/Users/me/.brew_logs/brew_update_20261025_030115.log",
    "upgrades_log": "/Users/me/.brew_logs/brew_update_20261025_030115.upgrades.log",
    "doctor_log": "/Users/me/.brew_logs/brew_update_20261025_030115.doctor.log",
    "security_log": "/Users/me/.brew_logs/brew_update_20261025_030115.security.log",
    "security_detailed_log": "/Users/me/.brew_logs/brew_update_20261025_030115.security.detailed.log",
    "security_json": "/Users/me/.brew_logs/brew_update_20261025_030115.security.json"
  }
}
```

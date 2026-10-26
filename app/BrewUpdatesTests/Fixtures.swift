// Sample documents trimmed from real script, grype and brew output.
enum Fixtures {
    static let summaryJSON = """
    {
      "schema_version": 1,
      "script_version": "2.2.0",
      "run_id": "20261025_030115",
      "trigger": "scheduled",
      "started_at": "2026-10-25T07:01:15Z",
      "finished_at": "2026-10-25T07:09:42Z",
      "duration_seconds": 507,
      "status": "partial",
      "exit_code": 1,
      "dry_run": false,
      "options": { "skip_casks": false, "skip_cleanup": false, "skip_security_scan": false, "packages": [] },
      "homebrew_version": "Homebrew 7.0.10",
      "outdated": {
        "formulae": [{ "name": "z3", "from": "5.3.1", "to": "5.3.2" }],
        "casks": [{ "name": "firefox", "from": "130.0", "to": "131.0" }]
      },
      "upgraded": { "formulae": [{ "name": "z3", "from": "5.3.1", "to": "5.3.2" }], "casks": [] },
      "failed": { "formulae": [], "casks": ["firefox"] },
      "skipped": { "excluded": ["node"], "pinned": [], "not_outdated": [] },
      "backup": { "created": true, "path": "/Users/me/.brew_backups/brew_backup_20261025_030115" },
      "doctor": { "status": "warnings" },
      "security": { "status": "completed", "vulnerability_count": 3 },
      "cleanup": { "status": "completed" },
      "files": {
        "log": "/Users/me/.brew_logs/brew_update_20261025_030115.log",
        "upgrades_log": null,
        "doctor_log": null,
        "security_log": null,
        "security_detailed_log": null,
        "security_json": null
      }
    }
    """

    static let grypeJSON = """
    {
      "matches": [
        {
          "vulnerability": {
            "id": "GHSA-0000-medium", "severity": "Medium",
            "dataSource": "https://github.com/advisories/GHSA-0000-medium",
            "fix": { "versions": [], "state": "not-fixed" }
          },
          "artifact": { "name": "libfoo", "version": "1.0", "type": "binary",
                        "locations": [{ "path": "/libfoo/1.0/lib/libfoo.dylib" }] }
        },
        {
          "vulnerability": {
            "id": "GHSA-5cgq-3rg8-m6cv", "severity": "Critical",
            "dataSource": "https://github.com/advisories/GHSA-5cgq-3rg8-m6cv",
            "description": "golang.org/x/crypto vulnerable to auth bypass",
            "fix": { "versions": ["0.52.0"], "state": "fixed" }
          },
          "artifact": { "name": "golang.org/x/crypto", "version": "v0.35.0", "type": "go-module",
                        "locations": [{ "path": "/gitleaks/8.30.1/bin/gitleaks" }] }
        },
        {
          "vulnerability": {
            "id": "GHSA-5cgq-3rg8-m6cv", "severity": "Critical",
            "dataSource": "https://github.com/advisories/GHSA-5cgq-3rg8-m6cv",
            "fix": { "versions": ["0.52.0"], "state": "fixed" }
          },
          "artifact": { "name": "golang.org/x/crypto", "version": "v0.35.0", "type": "go-module",
                        "locations": [{ "path": "/gitleaks/8.30.1/libexec/gitleaks-helper" }] }
        }
      ],
      "source": { "type": "directory", "target": "/opt/homebrew/Cellar" }
    }
    """

    static let brewInfoJSON = """
    {
      "formulae": [
        {
          "name": "z3", "full_name": "z3", "desc": "High-performance theorem prover",
          "homepage": "https://github.com/Z3Prover/z3", "tap": "homebrew/core",
          "versions": { "stable": "5.3.2" },
          "installed": [{ "version": "5.3.1", "installed_on_request": true, "time": 1790060435,
                          "runtime_dependencies": [{ "full_name": "abseil", "version": "20260817.0" }] }],
          "outdated": true, "pinned": false
        },
        {
          "name": "abseil", "full_name": "abseil", "desc": "C++ Common Libraries",
          "homepage": "https://abseil.io", "tap": "homebrew/core",
          "versions": { "stable": "20260817.0" },
          "installed": [{ "version": "20260817.0", "installed_on_request": false, "installed_as_dependency": null, "time": 1790060435 }],
          "outdated": false, "pinned": false
        }
      ],
      "casks": [
        {
          "token": "firefox", "full_token": "firefox", "name": ["Mozilla Firefox"], "desc": "Web browser",
          "homepage": "https://www.mozilla.org/firefox/", "tap": "homebrew/cask",
          "version": "131.0", "installed": "130.0", "installed_time": 1764137376,
          "outdated": false, "auto_updates": true
        }
      ]
    }
    """
}

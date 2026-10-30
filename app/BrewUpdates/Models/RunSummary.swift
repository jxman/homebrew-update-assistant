import Foundation

/// Decoded `brew_update_<RUN_ID>.summary.json` written by the script at the end of every run.
///
/// Mirrors docs/run-summary-schema.md (schema_version 1). Property names are camelCase;
/// the decoder converts them from the file's snake_case. Unknown fields are ignored, so
/// additive schema changes don't break decoding.
struct RunSummary: Codable, Sendable, Equatable {
    struct Options: Codable, Sendable, Equatable {
        let skipCasks: Bool
        let skipCleanup: Bool
        let skipSecurityScan: Bool
        let packages: [String]
    }

    /// A package with the version it was upgraded from and to.
    struct Package: Codable, Sendable, Hashable {
        let name: String
        let from: String
        let to: String
    }

    /// Formulae and casks reported separately, like the JSON.
    struct ByKind<Element: Codable & Sendable & Equatable>: Codable, Sendable, Equatable {
        let formulae: [Element]
        let casks: [Element]

        var all: [Element] { formulae + casks }
    }

    struct Skipped: Codable, Sendable, Equatable {
        let excluded: [String]
        let pinned: [String]
        let notOutdated: [String]
    }

    struct Backup: Codable, Sendable, Equatable {
        let created: Bool
        let path: String?
    }

    struct StepStatus: Codable, Sendable, Equatable {
        let status: String
    }

    struct Security: Codable, Sendable, Equatable {
        let status: String
        let vulnerabilityCount: Int
    }

    /// The `brew vulns` step (script 2.4.0+)
    struct Vulns: Codable, Sendable, Equatable {
        struct BySeverity: Codable, Sendable, Equatable {
            let critical: Int
            let high: Int
            let medium: Int
            let low: Int
            let unknown: Int
        }

        /// An outdated formula with findings in its installed version, checked before upgrading
        struct Outdated: Codable, Sendable, Equatable {
            let name: String
            let vulnerabilityCount: Int
        }

        let status: String
        let findingCount: Int
        let formulaCount: Int
        let bySeverity: BySeverity
        let checked: Int
        let skipped: Int
        let complete: Bool
        let beforeUpgrade: [Outdated]
    }

    /// An installed package Homebrew has deprecated or disabled (script 2.4.0+)
    struct Deprecation: Codable, Sendable, Hashable {
        let name: String
        let disabled: Bool
        /// When it was or will be disabled (or deprecated), `YYYY-MM-DD`
        let date: String?
        /// A symbol such as `deprecated_upstream`, or free text
        let reason: String?
        let replacement: String?
    }

    struct Deprecations: Codable, Sendable, Equatable {
        let status: String
        let formulae: [Deprecation]
        let casks: [Deprecation]
    }

    struct Files: Codable, Sendable, Equatable {
        let log: String?
        let upgradesLog: String?
        let doctorLog: String?
        let securityLog: String?
        let securityDetailedLog: String?
        let securityJson: String?
        let vulnsJson: String?
    }

    static let supportedSchemaVersion = 1

    let schemaVersion: Int
    let scriptVersion: String
    let runId: String
    let trigger: String
    let startedAt: Date
    let finishedAt: Date
    let durationSeconds: Int
    let status: String
    let exitCode: Int
    let dryRun: Bool
    let options: Options
    let homebrewVersion: String
    let outdated: ByKind<Package>
    let upgraded: ByKind<Package>
    let failed: ByKind<String>
    let skipped: Skipped
    let backup: Backup
    let doctor: StepStatus
    let security: Security
    /// nil in summaries from scripts before 2.4.0. Optional properties decode as nil when the
    /// key is missing, so older files still load.
    let vulns: Vulns?
    let deprecations: Deprecations?
    let cleanup: StepStatus
    let files: Files

    var runStatus: RunStatus { RunStatus(rawValue: status) ?? .unknown }

    static func decode(from data: Data) throws -> RunSummary {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RunSummary.self, from: data)
    }
}

extension RunSummary {
    /// Why this run has no report from a scanner, as a sentence fragment, from that step's status
    func missingReportReason(_ source: VulnerabilitySource) -> String {
        source == .grype ? Self.grypeMissingReason(security.status) : Self.brewVulnsMissingReason(vulns?.status)
    }

    private static func grypeMissingReason(_ status: String) -> String {
        switch status {
        case "dry_run": "it was a dry run, and dry runs skip grype"
        case "disabled": "grype scanning is turned off in Settings"
        case "unavailable": "grype isn't installed (brew install --cask grype)"
        case "skipped": "the run used --skip-security-scan"
        case "failed": "grype didn't produce a report; see the run's log"
        default: "the run ended before the scan"
        }
    }

    /// nil: the summary has no `vulns` object
    private static func brewVulnsMissingReason(_ status: String?) -> String {
        switch status {
        case nil: "it ran a script older than 2.4.0"
        case "disabled": "brew vulns is turned off in Settings"
        case "unavailable": "jq or brew vulns isn't available; see the run's log"
        case "skipped": "the run used --skip-security-scan"
        case "failed": "brew vulns didn't produce a report; see the run's log"
        default: "the run ended before the scan"
        }
    }
}

/// Outcome of a run. The first four come from the summary file; the rest are derived by the app.
enum RunStatus: String, Sendable, CaseIterable {
    case success
    case partial
    case failed
    case cancelled
    /// The run lock is held and this run has no summary yet
    case running
    /// Run from before script v2.2.0, which did not write summaries
    case legacy
    case unknown
}

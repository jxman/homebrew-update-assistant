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

    struct Files: Codable, Sendable, Equatable {
        let log: String?
        let upgradesLog: String?
        let doctorLog: String?
        let securityLog: String?
        let securityDetailedLog: String?
        let securityJson: String?
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

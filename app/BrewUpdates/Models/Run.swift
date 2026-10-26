import Foundation

/// The per-run files the script writes, named `brew_update_<RUN_ID>.<suffix>`.
enum RunFileKind: String, CaseIterable, Sendable, Identifiable {
    case log = "log"
    case upgrades = "upgrades.log"
    case doctor = "doctor.log"
    case security = "security.log"
    case securityDetailed = "security.detailed.log"
    case securityJSON = "security.json"
    case summary = "summary.json"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .log: "Main Log"
        case .upgrades: "Upgrades"
        case .doctor: "Doctor"
        case .security: "Security"
        case .securityDetailed: "Security Details"
        case .securityJSON: "Security JSON"
        case .summary: "Summary"
        }
    }

    /// Text logs worth showing in the log viewer (JSON files get dedicated views instead).
    var isViewableLog: Bool {
        switch self {
        case .securityJSON, .summary: false
        default: true
        }
    }
}

/// One script run: all files sharing a run ID, plus its summary when there is one.
struct Run: Identifiable, Sendable, Equatable {
    /// The run ID, `YYYYMMDD_HHMMSS` in local time
    let id: String
    let date: Date
    var files: [RunFileKind: URL]
    var summary: RunSummary?
    var status: RunStatus

    /// Log files present for this run, in a stable display order.
    var viewableLogs: [RunFileKind] {
        RunFileKind.allCases.filter { $0.isViewableLog && files[$0] != nil }
    }
}

/// Pure parsing helpers for run file names, kept separate from file I/O so they are easy to test.
enum RunCatalog {
    /// Parses `brew_update_20261025_030115.upgrades.log` into a run ID and file kind.
    static func parse(fileName: String) -> (runID: String, kind: RunFileKind)? {
        let pattern = #/^brew_update_(\d{8}_\d{6})\.(.+)$/#
        guard let match = fileName.wholeMatch(of: pattern),
              let kind = RunFileKind(rawValue: String(match.2)) else {
            return nil
        }
        return (String(match.1), kind)
    }

    /// Converts a run ID to a date in the local time zone (the script uses local `date`).
    static func date(fromRunID runID: String, timeZone: TimeZone = .current) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.date(from: runID)
    }

    /// Groups files into runs, newest first. Summaries are attached separately.
    static func groupRuns(fileURLs: [URL]) -> [Run] {
        var runsByID: [String: Run] = [:]
        for url in fileURLs {
            guard let (runID, kind) = parse(fileName: url.lastPathComponent),
                  let date = date(fromRunID: runID) else {
                continue
            }
            runsByID[runID, default: Run(id: runID, date: date, files: [:], summary: nil, status: .legacy)]
                .files[kind] = url
        }
        return runsByID.values.sorted { $0.id > $1.id }
    }
}

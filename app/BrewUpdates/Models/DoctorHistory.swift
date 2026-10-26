import Foundation

/// One doctor report and where it came from: a run's `*.doctor.log`, or a check from the app.
struct DoctorSnapshot: Identifiable, Equatable, Sendable {
    enum Source: Equatable, Sendable {
        case run(Run.ID)
        /// "Check Now" in the app; kept in memory only, since ~/.brew_logs belongs to the script
        case manual
    }

    let id: String
    let date: Date
    let source: Source
    let report: DoctorReport
    var logURL: URL?
}

/// How one issue has behaved across all the reports.
struct DoctorIssueHistory: Equatable, Sendable {
    let firstSeen: Date
    let lastSeen: Date
    /// Reports that contained the issue
    let occurrences: Int
    /// Reports checked in total
    let reportCount: Int
    /// The newest version of the issue (its items may have changed over time)
    let latest: DoctorIssue
    /// When it stopped appearing; nil while the newest report still has it
    let resolvedAt: Date?
}

/// Tracks issues across reports, matching them by `DoctorIssue.id`.
enum DoctorHistory {
    /// Every issue seen in `snapshots` (newest first), keyed by issue ID.
    static func histories(_ snapshots: [DoctorSnapshot]) -> [DoctorIssue.ID: DoctorIssueHistory] {
        var result: [DoctorIssue.ID: DoctorIssueHistory] = [:]
        let ids = Set(snapshots.flatMap { $0.report.issues.map(\.id) })

        for id in ids {
            // Indexes into the newest-first list of the reports containing this issue
            let indexes = snapshots.indices.filter { index in
                snapshots[index].report.issues.contains { $0.id == id }
            }
            guard let newest = indexes.first, let oldest = indexes.last,
                  let issue = snapshots[newest].report.issues.first(where: { $0.id == id }) else {
                continue
            }
            result[id] = DoctorIssueHistory(
                firstSeen: snapshots[oldest].date,
                lastSeen: snapshots[newest].date,
                occurrences: indexes.count,
                reportCount: snapshots.count,
                latest: issue,
                // The next newer report was the first without it
                resolvedAt: newest == 0 ? nil : snapshots[newest - 1].date
            )
        }
        return result
    }

    /// Issues that appeared before but not in the newest report, most recently fixed first.
    static func resolved(_ snapshots: [DoctorSnapshot], within interval: TimeInterval = 30 * 24 * 60 * 60) -> [DoctorIssueHistory] {
        guard let newest = snapshots.first else { return [] }
        return histories(snapshots).values
            .filter { $0.resolvedAt.map { newest.date.timeIntervalSince($0) <= interval } == true }
            .sorted { ($0.resolvedAt ?? .distantPast) > ($1.resolvedAt ?? .distantPast) }
    }
}

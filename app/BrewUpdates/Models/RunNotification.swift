import Foundation

/// The notification the app shows when a run finishes, built from the run's summary.
///
/// From script 2.5.0 on, the script leaves end-of-run notifications to the app whenever the
/// app is installed (`notify_run_finished` in the script), and records in the summary whether
/// the run wanted one. Older scripts send their own and don't record it, so the app stays
/// quiet for their runs instead of showing a second notification.
struct RunNotification: Equatable, Sendable {
    /// A run that finished longer ago than this is old news, e.g. when the app is opened the
    /// morning after a scheduled run
    static let maximumAge: TimeInterval = 15 * 60

    let runID: String
    let title: String
    let body: String
    /// Started from the app, so the user may be watching it finish
    let isFromApp: Bool

    init(summary: RunSummary) {
        runID = summary.runId
        isFromApp = summary.trigger == "app"

        let noun = summary.dryRun ? "Dry run" : "Update"
        let upgraded = summary.upgraded.all.count
        let failed = summary.failed.all.count
        let outdated = summary.outdated.all.count
        switch summary.runStatus {
        case .success where summary.dryRun:
            title = "Dry run finished"
            body = outdated > 0 ? "\(Self.packages(outdated)) can be upgraded" : "Everything is up to date"
        case .success:
            title = "Update finished"
            body = upgraded > 0 ? "Upgraded \(Self.packages(upgraded))" : "Everything is up to date"
        case .partial:
            title = "\(noun) finished with problems"
            body = failed > 0
                ? "Upgraded \(upgraded), \(failed) failed. Click to see the log."
                : "Exit code \(summary.exitCode). Click to see the log."
        case .cancelled:
            title = "\(noun) cancelled"
            body = "It stopped before finishing. Click to see the log."
        default:
            title = "\(noun) failed"
            body = "Exit code \(summary.exitCode). Click to see the log."
        }
    }

    /// Whether a run that has just finished should get a notification: it asked for one
    /// (`ENABLE_NOTIFICATIONS`, from the config file or the LaunchAgent), and it finished
    /// recently.
    static func shouldNotify(_ summary: RunSummary, now: Date) -> Bool {
        summary.notificationsEnabled == true && now.timeIntervalSince(summary.finishedAt) <= maximumAge
    }

    private static func packages(_ count: Int) -> String {
        count == 1 ? "1 package" : "\(count) packages"
    }
}

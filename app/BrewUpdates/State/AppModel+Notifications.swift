import Foundation

// MARK: - Notifications

extension AppModel {
    /// The last run considered for a notification, kept across launches so a run is never
    /// announced twice
    private static let lastNotifiedRunKey = "lastNotifiedRunID"

    /// Shows a notification when the newest finished run hasn't been considered yet: a run
    /// that just finished while the app was open, or the one the script started the app for.
    func notifyAboutFinishedRun() {
        guard let run = latestSummarizedRun, let summary = run.summary else { return }
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: Self.lastNotifiedRunKey) != run.id else { return }
        defaults.set(run.id, forKey: Self.lastNotifiedRunKey)
        guard RunNotification.shouldNotify(summary, now: .now) else { return }
        Task { await notifications.post(RunNotification(summary: summary)) }
    }
}

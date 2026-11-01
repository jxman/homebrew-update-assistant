import Foundation
import Testing

@Suite("Run notifications")
struct RunNotificationTests {
    /// The fixture summary (script 2.2.0, partial: z3 upgraded, firefox failed) with changes
    private static func summary(_ replacements: [String: String] = [:]) throws -> RunSummary {
        var json = Fixtures.summaryJSON
        for (old, new) in replacements {
            #expect(json.contains(old), "fixture has no \(old)")
            json = json.replacingOccurrences(of: old, with: new)
        }
        return try RunSummary.decode(from: Data(json.utf8))
    }

    private static let notificationsOn = [#""dry_run": false,"#: #""dry_run": false, "notifications_enabled": true,"#]
    private static let finishedAt = ISO8601DateFormatter().date(from: "2026-10-25T07:09:42Z")!

    @Test func describesAPartialRun() throws {
        let notification = RunNotification(summary: try Self.summary())
        #expect(notification.runID == "20261025_030115")
        #expect(notification.title == "Update finished with problems")
        #expect(notification.body == "Upgraded 1, 1 failed. Click to see the log.")
        #expect(!notification.isFromApp)
    }

    @Test func describesSuccessfulAndDryRuns() throws {
        let success = try Self.summary([#""status": "partial""#: #""status": "success""#])
        #expect(RunNotification(summary: success).title == "Update finished")
        #expect(RunNotification(summary: success).body == "Upgraded 1 package")

        let dryRun = try Self.summary([
            #""status": "partial""#: #""status": "success""#,
            #""dry_run": false"#: #""dry_run": true"#,
            #""trigger": "scheduled""#: #""trigger": "app""#
        ])
        let notification = RunNotification(summary: dryRun)
        #expect(notification.title == "Dry run finished")
        #expect(notification.body == "2 packages can be upgraded")
        #expect(notification.isFromApp)
    }

    @Test func describesFailedAndCancelledRuns() throws {
        let failed = try Self.summary([#""status": "partial""#: #""status": "failed""#])
        #expect(RunNotification(summary: failed).title == "Update failed")
        #expect(RunNotification(summary: failed).body == "Exit code 1. Click to see the log.")

        let cancelled = try Self.summary([#""status": "partial""#: #""status": "cancelled""#])
        #expect(RunNotification(summary: cancelled).title == "Update cancelled")
    }

    @Test func onlyRecentRunsThatAskedForOne() throws {
        let asked = try Self.summary(Self.notificationsOn)
        #expect(RunNotification.shouldNotify(asked, now: Self.finishedAt.addingTimeInterval(60)))
        // The app opened long after the run: old news
        #expect(!RunNotification.shouldNotify(asked, now: Self.finishedAt.addingTimeInterval(60 * 60)))
        // Turned off, or a script before 2.5.0 (no field), which sends its own notification
        let off = try Self.summary([#""dry_run": false,"#: #""dry_run": false, "notifications_enabled": false,"#])
        #expect(!RunNotification.shouldNotify(off, now: Self.finishedAt.addingTimeInterval(60)))
        #expect(!RunNotification.shouldNotify(try Self.summary(), now: Self.finishedAt.addingTimeInterval(60)))
    }

    @Test func readsTheSettingLikeTheScript() {
        #expect(BrewConfig.parse("ENABLE_NOTIFICATIONS=true").notificationsEnabled)
        #expect(BrewConfig.parse("ENABLE_NOTIFICATIONS=\"true\" # on").notificationsEnabled)
        #expect(!BrewConfig.parse("ENABLE_NOTIFICATIONS=yes").notificationsEnabled)
        #expect(!BrewConfig.parse("").notificationsEnabled)
    }
}

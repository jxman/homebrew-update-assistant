import Foundation
import Testing

@Suite("Doctor history")
struct DoctorHistoryTests {
    private func snapshot(_ day: Int, _ text: String) -> DoctorSnapshot {
        DoctorSnapshot(
            id: "\(day)",
            date: Date(timeIntervalSince1970: TimeInterval(day) * 86_400),
            source: .run("\(day)"),
            report: DoctorReport.parse(text)
        )
    }

    @Test func tracksFirstSeenOccurrencesAndResolution() throws {
        // Newest first: healthy on day 3, warnings on days 1 and 2
        let snapshots = [
            snapshot(3, DoctorFixtures.healthy),
            snapshot(2, DoctorFixtures.warnings),
            snapshot(1, DoctorFixtures.warnings)
        ]
        let history = try #require(DoctorHistory.histories(snapshots)[DoctorCheck.untrustedTaps.rawValue])
        #expect(history.firstSeen == snapshots[2].date)
        #expect(history.lastSeen == snapshots[1].date)
        #expect(history.occurrences == 2)
        #expect(history.reportCount == 3)
        #expect(history.resolvedAt == snapshots[0].date)

        #expect(DoctorHistory.resolved(snapshots).count == 2)
    }

    @Test func currentIssuesAreNotResolved() {
        let snapshots = [snapshot(2, DoctorFixtures.warnings), snapshot(1, DoctorFixtures.healthy)]
        #expect(DoctorHistory.histories(snapshots).values.allSatisfy { $0.resolvedAt == nil })
        #expect(DoctorHistory.resolved(snapshots).isEmpty)
    }

    @Test func oldFixesDropOffTheResolvedList() {
        let snapshots = [snapshot(60, DoctorFixtures.healthy), snapshot(2, DoctorFixtures.healthy), snapshot(1, DoctorFixtures.warnings)]
        #expect(DoctorHistory.resolved(snapshots).isEmpty)
    }
}

import Foundation
import Testing

// Swift Testing: each `@Test` is a test case and `#expect` records a failure without
// stopping the test (`#require` stops it). Run with ⌘U in Xcode or `xcodebuild test`.

@Suite("Run files")
struct RunCatalogTests {
    @Test func parsesRunFileNames() {
        let parsed = RunCatalog.parse(fileName: "brew_update_20261025_030115.security.detailed.log")
        #expect(parsed?.runID == "20261025_030115")
        #expect(parsed?.kind == .securityDetailed)
    }

    @Test(arguments: ["launchagent.log", "brew_update_2026_1.log", "brew_update_20261025_030115.unknown", "brew_backup_20261025_030115"])
    func ignoresOtherFiles(name: String) {
        #expect(RunCatalog.parse(fileName: name) == nil)
    }

    @Test func groupsFilesIntoRunsNewestFirst() throws {
        let dir = URL(filePath: "/tmp/logs")
        let names = [
            "brew_update_20261024_030000.log",
            "brew_update_20261025_030115.log",
            "brew_update_20261025_030115.summary.json",
            "brew_update_20261025_030115.upgrades.log",
            "launchagent.log"
        ]
        let runs = RunCatalog.groupRuns(fileURLs: names.map { dir.appending(path: $0) })

        #expect(runs.map(\.id) == ["20261025_030115", "20261024_030000"])
        let newest = try #require(runs.first)
        #expect(Set(newest.files.keys) == [.log, .summary, .upgrades])
        #expect(newest.viewableLogs == [.log, .upgrades])
        #expect(newest.status == .legacy)
    }

    @Test func runIDIsLocalTime() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        let date = try #require(RunCatalog.date(fromRunID: "20261025_030115", timeZone: utc))
        #expect(date == Date(timeIntervalSince1970: 1_792_897_275))
    }
}

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

@Suite("Run summary")
struct RunSummaryTests {
    @Test func decodesSchemaV1() throws {
        let summary = try RunSummary.decode(from: Data(Fixtures.summaryJSON.utf8))
        #expect(summary.schemaVersion == RunSummary.supportedSchemaVersion)
        #expect(summary.runStatus == .partial)
        #expect(summary.trigger == "scheduled")
        #expect(summary.durationSeconds == 507)
        #expect(summary.upgraded.formulae == [RunSummary.Package(name: "z3", from: "5.3.1", to: "5.3.2")])
        #expect(summary.failed.casks == ["firefox"])
        #expect(summary.skipped.excluded == ["node"])
        #expect(summary.files.upgradesLog == nil)
        #expect(summary.security.vulnerabilityCount == 3)
    }

    @Test func ignoresUnknownFieldsAndStatuses() throws {
        let json = Fixtures.summaryJSON
            .replacingOccurrences(of: "\"status\": \"partial\"", with: "\"status\": \"something_new\", \"new_field\": 1")
        let summary = try RunSummary.decode(from: Data(json.utf8))
        #expect(summary.runStatus == .unknown)
    }
}

@Suite("Log lines")
struct LogLineTests {
    @Test func parsesLevelsTimestampsAndPlainOutput() {
        let text = """
        [2026-10-25 03:01:15] [VERBOSE] Created directories
        [2026-10-25 03:01:33] [SUCCESS] ✓ Homebrew updated successfully
        ==> Upgrading z3
        \u{1B}[0;31m❌ Script failed\u{1B}[0m
        """
        let lines = LogLine.parse(text)

        #expect(lines.map(\.level) == [.verbose, .success, .output, .output])
        #expect(lines[0].timestamp == "2026-10-25 03:01:15")
        #expect(lines[1].message == "✓ Homebrew updated successfully")
        #expect(lines[2].timestamp == nil)
        #expect(lines[3].message == "❌ Script failed")
        #expect(lines.map(\.id) == [1, 2, 3, 4])
    }
}

@Suite("Schedule")
struct ScheduleTests {
    private func plist(_ interval: String) -> Data {
        Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
          <key>ProgramArguments</key>
          <array><string>/bin/bash</string><string>/Users/me/bin/brew-updates.command</string>
                 <string>--yes</string><string>--verbose</string></array>
          <key>StartCalendarInterval</key>\(interval)
        </dict></plist>
        """.utf8)
    }

    @Test func parsesDailySchedule() throws {
        let interval = "<dict><key>Hour</key><integer>3</integer><key>Minute</key><integer>0</integer></dict>"
        let schedule = try Schedule.parse(plistData: plist(interval))
        #expect(schedule.intervals == [CalendarInterval(minute: 0, hour: 3)])
        #expect(schedule.scriptArguments == ["--yes", "--verbose"])
        #expect(schedule.description(locale: Locale(identifier: "en_US")) == "Daily at 03:00")
    }

    @Test func parsesArrayOfIntervalsAndMapsWeekdays() throws {
        let schedule = try Schedule.parse(plistData: plist("""
        <array>
          <dict><key>Weekday</key><integer>0</integer><key>Hour</key><integer>9</integer><key>Minute</key><integer>30</integer></dict>
          <dict><key>Weekday</key><integer>3</integer><key>Hour</key><integer>21</integer></dict>
        </array>
        """))
        #expect(schedule.intervals.count == 2)
        #expect(schedule.description(locale: Locale(identifier: "en_US")) == "Sundays at 09:30; Wednesdays at 21:00")
        // launchd 0 = Sunday -> Foundation 1 = Sunday
        #expect(schedule.intervals[0].dateComponents.weekday == 1)
        #expect(schedule.intervals[1].dateComponents.weekday == 4)
    }

    @Test func nextRunPicksEarliestInterval() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let schedule = Schedule(
            intervals: [CalendarInterval(minute: 0, hour: 3), CalendarInterval(minute: 30, hour: 1)],
            scriptArguments: []
        )
        // 2026-10-25 02:00 UTC -> next is 03:00 the same day
        let now = Date(timeIntervalSince1970: 1_792_893_600)
        let next = try #require(schedule.nextRun(after: now, calendar: calendar))
        #expect(next == Date(timeIntervalSince1970: 1_792_897_200))
    }

    @Test func missingIntervalMeansNotScheduled() throws {
        let data = Data("<plist version=\"1.0\"><dict><key>Label</key><string>x</string></dict></plist>".utf8)
        let schedule = try Schedule.parse(plistData: data)
        #expect(schedule.intervals.isEmpty)
        #expect(schedule.description == "Not scheduled")
        #expect(schedule.nextRun(after: .now) == nil)
    }
}

@Suite("Config")
struct BrewConfigTests {
    @Test func parsesLikeTheScript() {
        let config = BrewConfig.parse("""
        # comment
        LOG_LEVEL=INFO  # Options: DEBUG, INFO
        EXCLUDED_FORMULAE="node@20  python@3.11"
        EXCLUDED_CASKS=''
        SECURITY_SCAN_SEVERITY=MEDIUM,CRITICAL # trailing
        SECURITY_SCAN_ENABLED=true
        NO_EQUALS_LINE
        """)
        #expect(config.values["LOG_LEVEL"] == "INFO")
        #expect(config.excludedFormulae == ["node@20", "python@3.11"])
        #expect(config.excludedCasks.isEmpty)
        #expect(config.securitySeverities == [.medium, .critical])
        #expect(config.securityScanEnabled)
        #expect(config.values["NO_EQUALS_LINE"] == nil)
    }

    @Test func defaultSeveritiesMatchScript() {
        #expect(BrewConfig().securitySeverities == [.high, .critical])
    }
}

@Suite("Security report")
struct VulnerabilityTests {
    @Test func parsesAndDeduplicatesGrypeMatches() throws {
        let vulnerabilities = try Vulnerability.parseGrypeReport(Data(Fixtures.grypeJSON.utf8))

        // Two matches share advisory + package + component + version -> collapsed to one
        #expect(vulnerabilities.count == 2)
        let first = try #require(vulnerabilities.first)
        #expect(first.severity == .critical)
        #expect(first.homebrewPackage == "gitleaks")
        #expect(first.component == "golang.org/x/crypto")
        #expect(first.fixVersions == ["0.52.0"])
        #expect(first.advisoryURL?.absoluteString == "https://github.com/advisories/GHSA-5cgq-3rg8-m6cv")
        #expect(vulnerabilities[1].severity == .medium)
        #expect(vulnerabilities[1].fixVersions.isEmpty)
    }

    @Test(arguments: [
        ("/gitleaks/8.30.1/bin/gitleaks", "gitleaks"),
        ("/opt/homebrew/Cellar/node/25.1.0/bin/node", "node"),
        ("", "Unknown")
    ])
    func extractsHomebrewPackage(path: String, expected: String) {
        #expect(Vulnerability.homebrewPackage(fromCellarPath: path) == expected)
    }

    @Test func severityOrdersMostSevereFirst() {
        #expect([Severity.low, .critical, .medium, .high].sorted() == [.critical, .high, .medium, .low])
        #expect(Severity(grype: "CRITICAL") == .critical)
        #expect(Severity(grype: "weird") == .unknown)
    }
}

@Suite("brew info")
struct InstalledPackageTests {
    @Test func parsesFormulaeAndCasks() throws {
        let packages = try InstalledPackage.parseBrewInfo(Data(Fixtures.brewInfoJSON.utf8))
        #expect(packages.map(\.id) == ["formula:abseil", "cask:firefox", "formula:z3"])

        let prover = try #require(packages.last)
        #expect(prover.isOutdated)
        #expect(prover.installedVersion == "5.3.1")
        #expect(prover.latestVersion == "5.3.2")
        #expect(prover.installedOnRequest)

        let abseil = try #require(packages.first)
        #expect(!abseil.installedOnRequest)

        let firefox = packages[1]
        #expect(firefox.kind == .cask)
        #expect(firefox.autoUpdates)
        #expect(firefox.summary == "Web browser")
    }

    @Test func exclusionUsesKindSpecificList() throws {
        let packages = try InstalledPackage.parseBrewInfo(Data(Fixtures.brewInfoJSON.utf8))
        let config = BrewConfig.parse("EXCLUDED_FORMULAE=z3\nEXCLUDED_CASKS=firefox")
        #expect(packages.filter(config.isExcluded).map(\.id) == ["cask:firefox", "formula:z3"])
    }
}

@Suite("Versions")
struct SemanticVersionTests {
    @Test func comparesNumerically() throws {
        let version = { (text: String) in try #require(SemanticVersion(text)) }
        #expect(try version("2.10.0") > version("2.9.9"))
        #expect(try version("2.2") == version("2.2.0"))
        #expect(try version("2.1.0") < SystemStatus.minimumScriptVersion)
        #expect(SemanticVersion("2.x") == nil)
    }
}

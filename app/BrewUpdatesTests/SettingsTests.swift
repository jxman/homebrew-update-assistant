import Foundation
import Testing

@Suite("Schedule editing")
struct ScheduleDraftTests {
    private let samplePlist = Data("""
    <?xml version="1.0" encoding="UTF-8"?>
    <plist version="1.0"><dict>
      <key>Label</key><string>com.user.brew-update</string>
      <key>ProgramArguments</key>
      <array><string>/bin/bash</string><string>/Users/me/bin/brew-updates.command</string>
             <string>--yes</string><string>--verbose</string></array>
      <key>StartCalendarInterval</key>
      <dict><key>Hour</key><integer>3</integer><key>Minute</key><integer>0</integer></dict>
      <key>StandardOutPath</key><string>/Users/me/.brew_logs/launchagent.log</string>
    </dict></plist>
    """.utf8)

    private func draft(_ intervals: [CalendarInterval], _ arguments: [String] = ["--yes"]) -> ScheduleDraft {
        ScheduleDraft(schedule: Schedule(intervals: intervals, scriptArguments: arguments))
    }

    @Test func readsDaily() {
        let draft = draft([CalendarInterval(minute: 15, hour: 4)])
        #expect(draft.frequency == .daily)
        #expect(draft.hour == 4 && draft.minute == 15)
        #expect(draft.isRepresentable)
    }

    @Test func readsWeeklyWithSundayAsSeven() {
        let draft = draft([CalendarInterval(minute: 0, hour: 9, weekday: 7), CalendarInterval(minute: 0, hour: 9, weekday: 3)])
        #expect(draft.frequency == .weekly)
        #expect(draft.weekdays == [0, 3])
    }

    @Test func readsMonthly() {
        let draft = draft([CalendarInterval(minute: 0, hour: 2, day: 15)])
        #expect(draft.frequency == .monthly)
        #expect(draft.dayOfMonth == 15)
    }

    @Test func flagsSchedulesItCantShow() {
        // Two different times a day
        #expect(!draft([CalendarInterval(minute: 0, hour: 3), CalendarInterval(minute: 0, hour: 15)]).isRepresentable)
        // Every hour (no Hour key)
        #expect(!draft([CalendarInterval(minute: 0)]).isRepresentable)
    }

    @Test func readsFlagsAndKeepsUnknownOnes() {
        let draft = draft([CalendarInterval(minute: 0, hour: 3)], ["-y", "-v", "--skip-casks", "--no-color"])
        #expect(draft.verbose && draft.skipCasks && !draft.skipCleanup)
        #expect(draft.otherArguments == ["--no-color"])
        #expect(draft.scriptArguments == ["--yes", "--verbose", "--skip-casks", "--no-color"])
    }

    @Test func buildsIntervalsPerFrequency() {
        var draft = ScheduleDraft()
        draft.hour = 6
        draft.minute = 45
        #expect(draft.intervals == [CalendarInterval(minute: 45, hour: 6)])

        draft.frequency = .weekly
        draft.weekdays = [5, 1]
        #expect(draft.intervals == [CalendarInterval(minute: 45, hour: 6, weekday: 1), CalendarInterval(minute: 45, hour: 6, weekday: 5)])

        draft.frequency = .monthly
        draft.dayOfMonth = 10
        #expect(draft.intervals == [CalendarInterval(minute: 45, hour: 6, day: 10)])
    }

    @Test func validates() {
        var draft = ScheduleDraft()
        draft.frequency = .weekly
        draft.weekdays = []
        #expect(draft.validationError != nil)
        draft.frequency = .monthly
        draft.dayOfMonth = 31
        #expect(draft.validationError != nil)
        draft.dayOfMonth = 28
        #expect(draft.validationError == nil)
    }

    @Test func rewritesPlistKeepingOtherKeys() throws {
        var draft = ScheduleDraft(schedule: try Schedule.parse(plistData: samplePlist))
        draft.frequency = .weekly
        draft.weekdays = [1, 4]
        draft.hour = 5
        draft.verbose = false
        draft.skipCleanup = true

        let updated = try draft.updatedPlist(samplePlist)
        let plist = try #require(try PropertyListSerialization.propertyList(from: updated, format: nil) as? [String: Any])
        #expect(plist["Label"] as? String == "com.user.brew-update")
        #expect(plist["StandardOutPath"] as? String == "/Users/me/.brew_logs/launchagent.log")
        #expect(plist["ProgramArguments"] as? [String] == ["/bin/bash", "/Users/me/bin/brew-updates.command", "--yes", "--skip-cleanup"])

        // Reading it back gives the same schedule
        let reread = try Schedule.parse(plistData: updated)
        #expect(reread == draft.schedule)
        #expect(ScheduleDraft(schedule: reread) == draft)
    }

    @Test func singleIntervalIsWrittenAsADictionary() throws {
        let updated = try ScheduleDraft().updatedPlist(samplePlist)
        let plist = try #require(try PropertyListSerialization.propertyList(from: updated, format: nil) as? [String: Any])
        #expect(plist["StartCalendarInterval"] as? [String: Int] == ["Hour": 3, "Minute": 0])
    }
}

@Suite("Config settings")
struct ConfigDraftTests {
    @Test func usesScriptDefaultsForMissingOrInvalidValues() {
        let draft = ConfigDraft(config: BrewConfig.parse("""
        MAX_BACKUP_COUNT=lots
        CLEANUP_BY_DEFAULT=yes
        SECURITY_SCAN_SEVERITY=SEVERE
        LOG_RETENTION_DAYS=7
        """))
        #expect(draft.maxBackupCount == 5)
        #expect(draft.cleanupByDefault)
        #expect(draft.securitySeverities == [.high, .critical])
        #expect(draft.logRetentionDays == 7)
        #expect(draft == {
            var expected = ConfigDraft()
            expected.logRetentionDays = 7
            return expected
        }())
    }

    @Test func reportsOnlyChangedKeysInScriptFormat() {
        let original = ConfigDraft(config: BrewConfig.parse("SECURITY_SCAN_ENABLED=true\nEXCLUDED_CASKS=\"zoom\""))
        var draft = original
        draft.securitySeverities = [.low, .critical, .medium]
        draft.excludedCasks.append("slack")
        draft.notificationsEnabled = true

        let changes = draft.changes(from: original)
        #expect(changes.map(\.key) == ["ENABLE_NOTIFICATIONS", "SECURITY_SCAN_SEVERITY", "EXCLUDED_CASKS"])
        #expect(changes.map(\.value) == ["true", "CRITICAL,MEDIUM,LOW", "zoom slack"])
        #expect(original.changes(from: original).isEmpty)
    }

    @Test func validates() {
        var draft = ConfigDraft()
        #expect(draft.validationError == nil)
        draft.securityScanEnabled = true
        draft.securitySeverities = []
        #expect(draft.validationError != nil)
        draft.securitySeverities = [.high]
        draft.excludedFormulae = ["ok", "not ok!"]
        #expect(draft.validationError != nil)
    }

    @Test func editorAppliesChangesKeepingComments() async throws {
        let home = try TemporaryHome()
        let paths = AppPaths(home: home.url)
        try "# mine\nLOG_RETENTION_DAYS=30 # a month\n".write(to: paths.configFile, atomically: true, encoding: .utf8)

        let config = try await ConfigEditor(paths: paths).apply([
            (key: "LOG_RETENTION_DAYS", value: "14"),
            (key: "ENABLE_NOTIFICATIONS", value: "true")
        ])
        #expect(config.values["LOG_RETENTION_DAYS"] == "14")
        let onDisk = try String(contentsOf: paths.configFile, encoding: .utf8)
        #expect(onDisk == "# mine\nLOG_RETENTION_DAYS=\"14\" # a month\nENABLE_NOTIFICATIONS=\"true\"\n")
    }
}

@Suite("LaunchAgent service")
struct LaunchAgentServiceTests {
    @Test func savesPlistAndKeepsBackupWithoutTouchingLaunchd() async throws {
        let home = try TemporaryHome()
        let paths = AppPaths(home: home.url)
        try FileManager.default.createDirectory(at: paths.launchAgentPlist.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = try ScheduleDraft().updatedPlist(Data("""
        <plist version="1.0"><dict><key>ProgramArguments</key><array><string>/bin/bash</string><string>s</string></array></dict></plist>
        """.utf8))
        try original.write(to: paths.launchAgentPlist)

        var draft = ScheduleDraft()
        draft.hour = 22
        // isLoaded: false, so no launchctl call is made against the real launchd
        try await LaunchAgentService(paths: paths).save(draft, isLoaded: false)

        let saved = try Schedule.parse(plistData: try Data(contentsOf: paths.launchAgentPlist))
        #expect(saved.intervals == [CalendarInterval(minute: 0, hour: 22)])
        #expect(try Data(contentsOf: paths.launchAgentPlist.appendingPathExtension("app-backup")) == original)
    }

    @Test func refusesWhenNotInstalled() async throws {
        let home = try TemporaryHome()
        await #expect(throws: LaunchAgentError.self) {
            try await LaunchAgentService(paths: AppPaths(home: home.url)).save(ScheduleDraft(), isLoaded: false)
        }
    }
}

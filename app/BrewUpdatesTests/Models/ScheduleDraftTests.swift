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

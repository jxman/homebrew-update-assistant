import Foundation
import Testing

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

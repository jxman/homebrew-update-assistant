import Foundation
import Testing

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

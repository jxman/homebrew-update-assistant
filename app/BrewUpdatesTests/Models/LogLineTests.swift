import Foundation
import Testing

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

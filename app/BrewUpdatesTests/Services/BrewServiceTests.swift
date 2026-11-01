import Foundation
import Testing

@Suite("Search path")
struct SearchPathTests {
    @Test func matchesTheLaunchAgentPath() {
        // Same as the PATH scripts/setup.sh writes into the LaunchAgent plist
        #expect(BrewService.searchPath(brewExecutable: URL(filePath: "/opt/homebrew/bin/brew"))
            == "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin")
    }
}

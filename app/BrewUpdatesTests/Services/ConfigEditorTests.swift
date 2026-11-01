import Foundation
import Testing

@Suite("Config editing")
struct ConfigEditingTests {
    private func package(_ name: String, _ kind: InstalledPackage.Kind = .formula) -> InstalledPackage {
        InstalledPackage(
            name: name, fullName: name, kind: kind, summary: nil, homepage: nil, tap: nil,
            installedVersion: "1", latestVersion: "2", isOutdated: true, isPinned: false,
            installedOnRequest: true, installedDate: nil, autoUpdates: false
        )
    }

    @Test func replacesLastAssignmentAndKeepsComments() {
        let text = "# my config\nEXCLUDED_FORMULAE=old\nEXCLUDED_FORMULAE=\"node\"  # keep node\nLOG_RETENTION_DAYS=30\n"
        let updated = BrewConfig.setting("EXCLUDED_FORMULAE", to: "node git", in: text)
        #expect(updated == "# my config\nEXCLUDED_FORMULAE=old\nEXCLUDED_FORMULAE=\"node git\"  # keep node\nLOG_RETENTION_DAYS=30\n")
    }

    @Test func appendsMissingKeyBeforeFinalNewline() {
        #expect(BrewConfig.setting("EXCLUDED_CASKS", to: "zoom", in: "") == "EXCLUDED_CASKS=\"zoom\"\n")
        #expect(BrewConfig.setting("EXCLUDED_CASKS", to: "zoom", in: "A=1") == "A=1\nEXCLUDED_CASKS=\"zoom\"")
    }

    @Test func addsAndRemovesExclusionsPerKind() throws {
        let start = "EXCLUDED_FORMULAE=\"node\"\n"
        let added = try BrewConfig.settingExclusion(true, for: [package("z3"), package("node"), package("zoom", .cask)], in: start)
        let config = BrewConfig.parse(added)
        #expect(config.values["EXCLUDED_FORMULAE"] == "node z3")
        #expect(config.values["EXCLUDED_CASKS"] == "zoom")

        let removed = try BrewConfig.settingExclusion(false, for: [package("node")], in: added)
        #expect(BrewConfig.parse(removed).values["EXCLUDED_FORMULAE"] == "z3")
    }

    @Test func refusesNamesTheScriptWouldReject() {
        #expect(throws: ConfigEditError.self) {
            try BrewConfig.settingExclusion(true, for: [package("c++lib")], in: "")
        }
    }

    @Test func editorWritesConfigFile() async throws {
        let home = try TemporaryHome()
        let paths = AppPaths(home: home.url)
        try "SECURITY_SCAN_ENABLED=true\n".write(to: paths.configFile, atomically: true, encoding: .utf8)

        let config = try await ConfigEditor(paths: paths).setExcluded(true, for: [package("z3")])
        #expect(config.excludedFormulae == ["z3"])
        let onDisk = try String(contentsOf: paths.configFile, encoding: .utf8)
        #expect(onDisk == "SECURITY_SCAN_ENABLED=true\nEXCLUDED_FORMULAE=\"z3\"\n")
    }
}

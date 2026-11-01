import Foundation
import Testing

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

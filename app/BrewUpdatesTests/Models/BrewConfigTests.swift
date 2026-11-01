import Foundation
import Testing

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

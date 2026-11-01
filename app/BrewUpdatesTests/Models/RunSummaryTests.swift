import Foundation
import Testing

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

@Suite("Run summary 2.4.0")
struct RunSummaryVulnsTests {
    private static let json = Fixtures.summaryJSON.replacingOccurrences(of: """
      "cleanup": { "status": "completed" },
    """, with: """
      "vulns": {
        "status": "completed", "finding_count": 3, "formula_count": 2,
        "by_severity": { "critical": 0, "high": 0, "medium": 2, "low": 0, "unknown": 1 },
        "checked": 79, "skipped": 18, "complete": false,
        "before_upgrade": [{ "name": "libssh2", "vulnerability_count": 1 }]
      },
      "deprecations": {
        "status": "completed",
        "formulae": [{ "name": "python@3.9", "disabled": true, "date": "2026-10-15",
                       "reason": "deprecated_upstream", "replacement": null }],
        "casks": []
      },
      "cleanup": { "status": "completed" },
    """)

    @Test func decodesVulnsAndDeprecations() throws {
        #expect(Self.json != Fixtures.summaryJSON)
        let summary = try RunSummary.decode(from: Data(Self.json.utf8))
        let vulns = try #require(summary.vulns)
        #expect(vulns.findingCount == 3)
        #expect(vulns.bySeverity.medium == 2)
        #expect(vulns.beforeUpgrade == [RunSummary.Vulns.Outdated(name: "libssh2", vulnerabilityCount: 1)])
        let deprecation = try #require(summary.deprecations?.formulae.first)
        #expect(deprecation.disabled)
        #expect(deprecation.replacement == nil)
    }

    @Test func olderSummariesHaveNeither() throws {
        let summary = try RunSummary.decode(from: Data(Fixtures.summaryJSON.utf8))
        #expect(summary.vulns == nil)
        #expect(summary.deprecations == nil)
        #expect(summary.files.vulnsJson == nil)
    }

    @Test func vulnsReportIsARunFile() throws {
        let parsed = try #require(RunCatalog.parse(fileName: "brew_update_20261029_224405.vulns.json"))
        #expect(parsed.kind == .vulnsJSON)
        #expect(!parsed.kind.isViewableLog)
        // The script's temporary file for the before-upgrade check isn't one
        #expect(RunCatalog.parse(fileName: "brew_update_20261029_224405.vulns-before.tmp") == nil)
    }
}

@Suite("Missing scan reports")
struct MissingReportTests {
    @Test func explainsFromStepStatus() throws {
        let summary = try RunSummary.decode(from: Data(
            Fixtures.summaryJSON.replacingOccurrences(of: #""status": "completed", "vulnerability_count""#,
                                                      with: #""status": "dry_run", "vulnerability_count""#).utf8
        ))
        #expect(summary.missingReportReason(.grype) == "it was a dry run, and dry runs skipped grype before script 2.4.1")
        // No vulns object: the run's script predates brew vulns
        #expect(summary.missingReportReason(.brewVulns) == "it ran a script older than 2.4.0")
    }
}

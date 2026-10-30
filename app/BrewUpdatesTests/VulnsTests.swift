import Foundation
import Testing

// Trimmed from real `brew vulns --json` output; the gitleaks finding is made up to share an
// alias with the grype fixture's GHSA, so the two scanners can be matched up.
private let brewVulnsJSON = """
{
  "findings": [
    {
      "formula": "libssh2", "version": "1.11.1", "tag": "1.11.1",
      "repo_url": "https://github.com/libssh2/libssh2",
      "vulnerabilities": [
        { "id": "OSV-2025-433", "severity": "UNKNOWN", "summary": "Null-dereference READ in _libssh2_packet_add",
          "aliases": [], "fixed_versions": ["2dae3024897e1898d389835151f4e9606227721d"] }
      ],
      "patched": [
        { "id": "CVE-2025-15661", "severity": "UNKNOWN", "summary": "Heap Buffer Over-read",
          "aliases": [], "fixed_versions": [] }
      ]
    },
    {
      "formula": "gitleaks", "version": "8.30.1", "tag": "v8.30.1",
      "repo_url": "https://github.com/gitleaks/gitleaks",
      "vulnerabilities": [
        { "id": "CVE-2026-1111", "severity": "CRITICAL", "summary": "auth bypass",
          "aliases": ["GHSA-5cgq-3rg8-m6cv"], "fixed_versions": ["8.30.2"] }
      ],
      "patched": []
    }
  ],
  "skipped_formulae": ["hashicorp/tap/terraform", "libtiff"],
  "unscanned_formulae": {},
  "outdated_without_sbom": [],
  "checked": 79,
  "complete": false
}
"""

@Suite("brew vulns report")
struct BrewVulnsTests {
    @Test func parsesFindingsAndCoverage() throws {
        let report = try Vulnerability.parseBrewVulnsReport(Data(brewVulnsJSON.utf8))
        #expect(report.checkedCount == 79)
        #expect(report.skippedFormulae == ["hashicorp/tap/terraform", "libtiff"])
        #expect(!report.isComplete)

        // Patched findings are left out; most severe first
        #expect(report.findings.map(\.advisoryID) == ["CVE-2026-1111", "OSV-2025-433"])
        let critical = try #require(report.findings.first)
        #expect(critical.severity == .critical)
        #expect(critical.homebrewPackage == "gitleaks")
        #expect(critical.sources == [.brewVulns])
        #expect(critical.advisoryURL?.absoluteString == "https://osv.dev/vulnerability/CVE-2026-1111")
        #expect(report.findings[1].severity == .unknown)
    }

    @Test func shortensCommitFixes() throws {
        let report = try Vulnerability.parseBrewVulnsReport(Data(brewVulnsJSON.utf8))
        #expect(report.findings[1].fixVersionsText == "commit 2dae302")
        #expect(report.findings[0].fixVersionsText == "8.30.2")
    }

    @Test func combinesScannersByPackageAndAlias() throws {
        let grype = try Vulnerability.parseGrypeReport(Data(Fixtures.grypeJSON.utf8))
        let brewVulns = try Vulnerability.parseBrewVulnsReport(Data(brewVulnsJSON.utf8)).findings
        let combined = Vulnerability.combine(grype: grype, brewVulns: brewVulns)

        // gitleaks's advisory is one row found by both; libssh2 and libfoo by one each
        #expect(combined.count == 3)
        let shared = try #require(combined.first { $0.homebrewPackage == "gitleaks" })
        #expect(shared.sources == [.grype, .brewVulns])
        #expect(shared.sourcesText == "Grype + brew vulns")
        #expect(shared.component == "golang.org/x/crypto")
        #expect(combined.first { $0.homebrewPackage == "libssh2" }?.sources == [.brewVulns])
        #expect(combined.first { $0.homebrewPackage == "libfoo" }?.sources == [.grype])
    }

    @Test func sameAdvisoryInAnotherPackageIsNotMerged() throws {
        let grype = try Vulnerability.parseGrypeReport(Data(Fixtures.grypeJSON.utf8))
        let other = try Vulnerability.parseBrewVulnsReport(Data(
            brewVulnsJSON.replacingOccurrences(of: "\"formula\": \"gitleaks\"", with: "\"formula\": \"trivy\"").utf8
        )).findings
        #expect(Vulnerability.combine(grype: grype, brewVulns: other).count == 4)
    }

    @Test func rejectsOtherJSON() {
        #expect(throws: (any Error).self) { try Vulnerability.parseBrewVulnsReport(Data(#"{"matches": []}"#.utf8)) }
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

@Suite("Deprecations")
struct DeprecationTests {
    /// The keys `brew info --json=v2` has on every formula and cask (python@3.9 is real)
    private static let brewInfoJSON = Fixtures.brewInfoJSON
        .replacingOccurrences(
            of: #""outdated": true, "pinned": false"#,
            with: #""outdated": true, "pinned": false, "deprecated": true, "deprecation_date": "2025-10-15", "#
                + #""deprecation_reason": "deprecated_upstream", "deprecation_replacement_formula": "z3-next", "#
                + #""disabled": false"#
        )
        .replacingOccurrences(
            of: #""outdated": false, "auto_updates": true"#,
            with: #""outdated": false, "auto_updates": true, "deprecated": true, "disabled": true, "#
                + #""disable_date": "2026-09-01", "disable_reason": "Upstream stopped shipping macOS builds", "#
                + #""disable_replacement_cask": null"#
        )

    @Test func readsDeprecationFromBrewInfo() throws {
        #expect(Self.brewInfoJSON.components(separatedBy: "\"deprecated\"").count == 3)
        let packages = try InstalledPackage.parseBrewInfo(Data(Self.brewInfoJSON.utf8))
        let prover = try #require(packages.first { $0.name == "z3" })
        #expect(prover.deprecation == PackageDeprecation(
            isDisabled: false, date: "2025-10-15", reason: "deprecated_upstream", replacement: "z3-next"
        ))
        #expect(prover.deprecation?.description == "deprecated since 2025-10-15 (deprecated upstream), use z3-next instead")

        // Disabled wins, with its own date and reason (free text is kept as is)
        let firefox = try #require(packages.first { $0.name == "firefox" })
        #expect(firefox.deprecation?.isDisabled == true)
        #expect(firefox.deprecation?.description == "disabled since 2026-09-01 (Upstream stopped shipping macOS builds)")

        #expect(packages.first { $0.name == "abseil" }?.deprecation == nil)
    }

    @Test func doctorIssuePerKindReplacesBrewDoctors() throws {
        let packages = try InstalledPackage.parseBrewInfo(Data(Self.brewInfoJSON.utf8))
        let formulae = try #require(DoctorIssue.deprecatedPackages(in: packages, kind: .formula))
        #expect(formulae.check == .deprecatedFormulae)
        #expect(formulae.items == ["z3"])
        #expect(formulae.details.contains("use z3-next instead"))
        let casks = try #require(DoctorIssue.deprecatedPackages(in: packages, kind: .cask))
        #expect(casks.check == .deprecatedCasks)

        let fromDoctor = DoctorIssue(
            level: .warning, headline: "Some installed formulae are deprecated or disabled!",
            details: "z3", check: .deprecatedFormulae, items: ["z3"], commands: [], links: []
        )
        let merged = DoctorIssue.merging(report: [fromDoctor], app: [formulae, casks])
        #expect(merged.count == 2)
        #expect(merged.first { $0.check == .deprecatedFormulae } == formulae)
    }

    @Test func noIssueWithoutDeprecations() throws {
        let packages = try InstalledPackage.parseBrewInfo(Data(Fixtures.brewInfoJSON.utf8))
        #expect(DoctorIssue.deprecatedPackages(in: packages, kind: .formula) == nil)
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

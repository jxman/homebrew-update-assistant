import Foundation
import Testing

@Suite("Deprecations")
struct PackageDeprecationTests {
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

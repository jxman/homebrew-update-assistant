import Foundation
import Testing

@Suite("Uninstall")
struct UninstallPlanTests {
    private func package(
        _ name: String, _ kind: InstalledPackage.Kind = .formula, fullName: String? = nil, needs: [String] = []
    ) -> InstalledPackage {
        InstalledPackage(
            name: name, fullName: fullName ?? name, kind: kind, summary: nil, homepage: nil, tap: nil,
            installedVersion: "1", latestVersion: "1", isOutdated: false, isPinned: false,
            installedOnRequest: true, installedDate: nil, autoUpdates: false, runtimeDependencies: needs
        )
    }

    @Test func readsRuntimeDependenciesFromBrewInfo() throws {
        let packages = try InstalledPackage.parseBrewInfo(Data(Fixtures.brewInfoJSON.utf8))
        #expect(packages.first { $0.name == "z3" }?.runtimeDependencies == ["abseil"])
        #expect(packages.first { $0.name == "z3" }?.directDependencies == ["abseil"])
    }

    @Test func usesKindFlagAndFullNames() {
        let terraform = package("terraform", fullName: "hashicorp/tap/terraform")
        let plan = UninstallPlan(packages: [terraform, package("jq")], installed: [terraform, package("jq")])
        #expect(plan.arguments == ["uninstall", "--formula", "hashicorp/tap/terraform", "jq"])

        let cask = package("firefox", .cask)
        #expect(UninstallPlan(packages: [cask], installed: [cask]).arguments == ["uninstall", "--cask", "firefox"])
        // Mixed kinds: no flag, brew works out each one
        #expect(UninstallPlan(packages: [cask, package("jq")], installed: []).arguments == ["uninstall", "firefox", "jq"])
    }

    @Test func warnsAboutPackagesOthersStillNeed() {
        let installed = [package("oniguruma"), package("jq", needs: ["oniguruma"]), package("gh")]
        let plan = UninstallPlan(packages: [installed[0]], installed: installed)
        #expect(plan.blockers == ["oniguruma": ["jq"]])
        #expect(plan.message.contains("because jq needs it"))

        // Removing the dependent at the same time is fine
        #expect(UninstallPlan(packages: [installed[0], installed[1]], installed: installed).blockers.isEmpty)
    }

    @Test func offersToRemoveWhatNeedsABlockedFormula() {
        // gh needs jq, which needs oniguruma: removing oniguruma takes all three
        let installed = [
            package("oniguruma"), package("jq", needs: ["oniguruma"]),
            package("gh", needs: ["jq", "oniguruma"]), package("wget")
        ]
        let plan = UninstallPlan(packages: [installed[0]], installed: installed)
        #expect(plan.isBlocked)
        #expect(plan.blockingPackages.map(\.name) == ["gh", "jq"])

        let expanded = plan.includingDependents(in: installed)
        #expect(!expanded.isBlocked)
        #expect(Set(expanded.names) == ["oniguruma", "jq", "gh"])
        #expect(plan.blockedMessage(expanded: expanded).contains("also uninstall gh, jq"))
    }

    @Test func addsDependentsOfDependentsUntilNothingIsBlocked() {
        // Only actionlint needs shellcheck directly; ci-tool needs actionlint
        let installed = [package("shellcheck"), package("actionlint", needs: ["shellcheck"]), package("ci-tool", needs: ["actionlint"])]
        let expanded = UninstallPlan(packages: [installed[0]], installed: installed).includingDependents(in: installed)
        #expect(expanded.names == ["shellcheck", "actionlint", "ci-tool"])
        #expect(!UninstallPlan(packages: [installed[2]], installed: installed).isBlocked)
    }

    @Test func refusesNamesInstalledAsBothKindsInMixedSelections() {
        let installed = [package("docker"), package("docker", .cask), package("jq")]
        #expect(UninstallPlan(packages: [installed[1], installed[2]], installed: installed).ambiguousNames == ["docker"])
        // One kind only: the flag makes it unambiguous
        #expect(UninstallPlan(packages: [installed[1]], installed: installed).ambiguousNames.isEmpty)
    }
}

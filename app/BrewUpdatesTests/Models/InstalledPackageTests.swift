import Foundation
import Testing

@Suite("brew info")
struct InstalledPackageTests {
    @Test func parsesFormulaeAndCasks() throws {
        let packages = try InstalledPackage.parseBrewInfo(Data(Fixtures.brewInfoJSON.utf8))
        #expect(packages.map(\.id) == ["formula:abseil", "cask:firefox", "formula:z3"])

        let prover = try #require(packages.last)
        #expect(prover.isOutdated)
        #expect(prover.installedVersion == "5.3.1")
        #expect(prover.latestVersion == "5.3.2")
        #expect(prover.installedOnRequest)

        let abseil = try #require(packages.first)
        #expect(!abseil.installedOnRequest)

        let firefox = packages[1]
        #expect(firefox.kind == .cask)
        #expect(firefox.autoUpdates)
        #expect(firefox.summary == "Web browser")
    }

    @Test func readsInstallDatesForFormulaeAndCasks() throws {
        let packages = try InstalledPackage.parseBrewInfo(Data(Fixtures.brewInfoJSON.utf8))
        #expect(packages[0].installedDate == Date(timeIntervalSince1970: 1_790_060_435))
        #expect(packages[1].installedDate == Date(timeIntervalSince1970: 1_764_137_376))
        // Sorting by date puts the older cask first
        #expect(packages.sorted(using: KeyPathComparator(\.installedSortDate)).first?.name == "firefox")
    }

    @Test func unknownInstallDateSortsAsOldest() throws {
        let packages = try InstalledPackage.parseBrewInfo(Data(Fixtures.brewInfoJSON.utf8))
        let undated = InstalledPackage(
            name: "undated", fullName: "undated", kind: .formula, summary: nil, homepage: nil, tap: nil,
            installedVersion: "1", latestVersion: "1", isOutdated: false, isPinned: false,
            installedOnRequest: true, installedDate: nil, autoUpdates: false
        )
        #expect(undated.installedSortDate < packages[1].installedSortDate)
    }

    @Test func exclusionUsesKindSpecificList() throws {
        let packages = try InstalledPackage.parseBrewInfo(Data(Fixtures.brewInfoJSON.utf8))
        let config = BrewConfig.parse("EXCLUDED_FORMULAE=z3\nEXCLUDED_CASKS=firefox")
        #expect(packages.filter(config.isExcluded).map(\.id) == ["cask:firefox", "formula:z3"])
    }
}

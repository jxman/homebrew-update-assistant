import Testing

@Suite("Package dependencies")
struct PackageDependenciesTests {
    /// Like the real awscli: it needs aws-c-auth, which needs aws-c-io; both need aws-c-common
    private let installed = [
        PackageDependenciesTests.formula("awscli", onRequest: true, direct: ["aws-c-auth", "aws-c-io"], indirect: ["aws-c-common"]),
        PackageDependenciesTests.formula("aws-sam-cli", onRequest: true, direct: ["aws-c-auth"], indirect: ["aws-c-io", "aws-c-common"]),
        PackageDependenciesTests.formula("aws-c-auth", direct: ["aws-c-io", "aws-c-common"]),
        PackageDependenciesTests.formula("aws-c-io", direct: ["aws-c-common"]),
        PackageDependenciesTests.formula("aws-c-common"),
        PackageDependenciesTests.formula("tf-lib", fullName: "hashicorp/tap/tf-lib"),
        PackageDependenciesTests.formula("terraform", onRequest: true, direct: ["hashicorp/tap/tf-lib"]),
        PackageDependenciesTests.formula("leftover"),
        // Like ada-url: built when simdutf needed icu4c@78, which it still lists indirectly
        PackageDependenciesTests.formula("ada-url", direct: ["simdutf"], indirect: ["icu4c@78"]),
        PackageDependenciesTests.formula("simdutf", direct: ["icu4c@79"]),
        PackageDependenciesTests.formula("icu4c@78"),
        PackageDependenciesTests.formula("icu4c@79")
    ]

    @Test func showsWhatALibraryNeedsAndWhatNeedsIt() {
        let auth = PackageDependenciesTests.dependencies("aws-c-auth", in: installed)
        #expect(auth.needs.map(\.name) == ["aws-c-common", "aws-c-io"])
        #expect(auth.neededBy.map(\.name) == ["aws-sam-cli", "awscli"])
        #expect(auth.installedFor.map(\.name) == ["aws-sam-cli", "awscli"])
        #expect(!auth.isLeftover)
    }

    @Test func installedForIncludesIndirectUsers() {
        // Nothing installed on request declares aws-c-common, but both CLIs need it through others
        let common = PackageDependenciesTests.dependencies("aws-c-common", in: installed)
        #expect(common.neededBy.map(\.name) == ["aws-c-auth", "aws-c-io"])
        #expect(common.installedFor.map(\.name) == ["aws-sam-cli", "awscli"])
        #expect(common.needs.isEmpty)
    }

    @Test func countsIndirectDependencies() {
        let cli = PackageDependenciesTests.dependencies("awscli", in: installed)
        #expect(cli.needs.map(\.name) == ["aws-c-auth", "aws-c-io"])
        #expect(cli.indirectCount == 1)
        #expect(cli.neededBy.isEmpty)
    }

    @Test func matchesTapFormulaeByFullName() {
        let lib = PackageDependenciesTests.dependencies("tf-lib", in: installed)
        #expect(lib.neededBy.map(\.name) == ["terraform"])
        #expect(PackageDependenciesTests.dependencies("terraform", in: installed).needs.map(\.name) == ["tf-lib"])
    }

    @Test func flagsDependenciesNothingNeeds() {
        #expect(PackageDependenciesTests.dependencies("leftover", in: installed).isLeftover)
    }

    @Test func keepsDependenciesOnlyListedIndirectly() {
        // brew autoremove keeps icu4c@78 because ada-url still lists it, so it isn't a leftover
        let old = PackageDependenciesTests.dependencies("icu4c@78", in: installed)
        #expect(old.neededBy.isEmpty)
        #expect(old.indirectlyNeededBy.map(\.name) == ["ada-url"])
        #expect(old.installedFor.isEmpty)
        #expect(!old.isLeftover)
    }

    private static func dependencies(_ name: String, in installed: [InstalledPackage]) -> PackageDependencies {
        PackageDependencies(of: installed.first { $0.name == name }!, in: installed)
    }

    @Test func listsDirectDependentsByFullName() {
        let dependents = InstalledPackage.dependents(in: installed)
        #expect(dependents["aws-c-auth"] == ["aws-sam-cli", "awscli"])
        #expect(dependents["aws-c-common"] == ["aws-c-auth", "aws-c-io"])
        // Indirect needs don't count: awscli only reaches aws-c-common through others
        #expect(dependents["awscli"] == nil)
    }

    private static func formula(
        _ name: String, fullName: String? = nil, onRequest: Bool = false, direct: [String] = [], indirect: [String] = []
    ) -> InstalledPackage {
        InstalledPackage(
            name: name, fullName: fullName ?? name, kind: .formula, summary: nil, homepage: nil, tap: nil,
            installedVersion: "1", latestVersion: "1", isOutdated: false, isPinned: false,
            installedOnRequest: onRequest, installedDate: nil, autoUpdates: false,
            runtimeDependencies: direct + indirect, directDependencies: direct
        )
    }
}

import Foundation

/// How an installed formula relates to the other installed packages, worked out from each
/// formula's runtime dependencies in `brew info` (no extra brew calls).
struct PackageDependencies: Equatable, Sendable {
    /// Installed formulae this one declares as dependencies
    let needs: [InstalledPackage]
    /// How many more it needs through those (dependencies of dependencies)
    let indirectCount: Int
    /// Installed formulae that declare this one as a dependency
    let neededBy: [InstalledPackage]
    /// Installed formulae that need it only through other dependencies
    let indirectlyNeededBy: [InstalledPackage]
    /// Packages installed on request that need this one, directly or not: why a dependency is
    /// installed. Empty for a dependency nothing needs any more.
    let installedFor: [InstalledPackage]

    init(of package: InstalledPackage, in installed: [InstalledPackage]) {
        // Dependencies are recorded by full name: `abseil` for core, `hashicorp/tap/x` for taps
        func isListed(_ names: [String]) -> Bool {
            names.contains(package.fullName) || names.contains(package.name)
        }
        let byName = Dictionary(installed.map { ($0.fullName, $0) }, uniquingKeysWith: { first, _ in first })

        needs = package.directDependencies.compactMap { byName[$0] }.sorted(by: Self.byName)
        indirectCount = Set(package.runtimeDependencies).subtracting(package.directDependencies).count
        let others = installed.filter { $0.id != package.id }
        neededBy = others.filter { isListed($0.directDependencies) }.sorted(by: Self.byName)
        indirectlyNeededBy = others
            .filter { isListed($0.runtimeDependencies) && !isListed($0.directDependencies) }
            .sorted(by: Self.byName)
        installedFor = others.filter { $0.installedOnRequest && isListed($0.runtimeDependencies) }.sorted(by: Self.byName)
    }

    /// No installed formula needs it, directly or not: usually left behind when the package
    /// that pulled it in was uninstalled. Same rule as `brew autoremove`, which removes these.
    var isLeftover: Bool { neededBy.isEmpty && indirectlyNeededBy.isEmpty }

    private static func byName(_ lhs: InstalledPackage, _ rhs: InstalledPackage) -> Bool {
        lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}

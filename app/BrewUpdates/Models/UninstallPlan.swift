import Foundation

/// A `brew uninstall` of the packages selected in the Installed view, checked before it runs.
struct UninstallPlan: Equatable, Sendable {
    let packages: [InstalledPackage]
    /// Selected formula -> installed formulae (not being removed) that still need it.
    /// brew refuses to uninstall these, so the confirmation warns about them up front.
    let blockers: [String: [String]]
    /// Names installed both as a formula and a cask. With a mixed selection there is no
    /// `--formula`/`--cask` flag to say which is meant, so these are refused.
    let ambiguousNames: [String]

    init(packages: [InstalledPackage], installed: [InstalledPackage]) {
        self.packages = packages
        let removing = Set(packages.map(\.id))

        var blockers: [String: [String]] = [:]
        for package in packages where package.kind == .formula {
            let users = installed
                .filter { !removing.contains($0.id) }
                .filter { $0.runtimeDependencies.contains(package.fullName) || $0.runtimeDependencies.contains(package.name) }
                .map(\.name)
            if !users.isEmpty {
                blockers[package.name] = users.sorted()
            }
        }
        self.blockers = blockers

        let isMixed = Set(packages.map(\.kind)).count > 1
        let formulaNames = Set(installed.filter { $0.kind == .formula }.map(\.name))
        let caskNames = Set(installed.filter { $0.kind == .cask }.map(\.name))
        ambiguousNames = isMixed ? packages.map(\.name).filter { formulaNames.contains($0) && caskNames.contains($0) } : []
    }

    var names: [String] { packages.map(\.name) }

    /// Arguments for `brew`. Full names (`hashicorp/tap/terraform`) so a tap's package is never
    /// mistaken for a core one. `--formula`/`--cask` when the selection is all one kind.
    var arguments: [String] {
        let kinds = Set(packages.map(\.kind))
        let flag: [String] = switch kinds {
        case [.formula]: ["--formula"]
        case [.cask]: ["--cask"]
        default: []
        }
        return ["uninstall"] + flag + packages.map(\.fullName)
    }

    /// Text for the confirmation dialog
    var message: String {
        var parts = ["Runs brew uninstall for \(names.joined(separator: ", "))."]
        for (name, users) in blockers.sorted(by: { $0.key < $1.key }) {
            parts.append("brew will refuse to remove \(name) because \(users.joined(separator: ", ")) "
                + "\(users.count == 1 ? "needs" : "need") it. Select those too to remove them together.")
        }
        if packages.contains(where: { $0.kind == .formula }) {
            parts.append("Dependencies nothing else needs are left installed; brew autoremove removes them.")
        }
        let needsAdmin = packages.filter(\.uninstallNeedsAdmin).map(\.name)
        if !needsAdmin.isEmpty {
            parts.append("macOS will probably ask for your administrator password: \(needsAdmin.joined(separator: ", ")) "
                + "installed system files that only an administrator can remove.")
        }
        return parts.joined(separator: "\n\n")
    }
}

import Foundation

/// A `brew uninstall` of the packages selected in the Installed view, checked before it runs.
struct UninstallPlan: Equatable, Sendable {
    let packages: [InstalledPackage]
    /// Selected formula -> installed formulae (not being removed) that still need it.
    /// brew refuses to uninstall these, so the confirmation warns about them up front.
    let blockers: [String: [String]]
    /// The installed formulae named in `blockers`
    let blockingPackages: [InstalledPackage]
    /// Names installed both as a formula and a cask. With a mixed selection there is no
    /// `--formula`/`--cask` flag to say which is meant, so these are refused.
    let ambiguousNames: [String]

    init(packages: [InstalledPackage], installed: [InstalledPackage]) {
        self.packages = packages
        let removing = Set(packages.map(\.id))

        var blockers: [String: [String]] = [:]
        var blocking: [InstalledPackage] = []
        for package in packages where package.kind == .formula {
            let users = installed
                .filter { !removing.contains($0.id) }
                .filter { $0.runtimeDependencies.contains(package.fullName) || $0.runtimeDependencies.contains(package.name) }
            if !users.isEmpty {
                blockers[package.name] = users.map(\.name).sorted()
                blocking += users.filter { user in !blocking.contains { $0.id == user.id } }
            }
        }
        self.blockers = blockers
        blockingPackages = blocking.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        let isMixed = Set(packages.map(\.kind)).count > 1
        let formulaNames = Set(installed.filter { $0.kind == .formula }.map(\.name))
        let caskNames = Set(installed.filter { $0.kind == .cask }.map(\.name))
        ambiguousNames = isMixed ? packages.map(\.name).filter { formulaNames.contains($0) && caskNames.contains($0) } : []
    }

    var names: [String] { packages.map(\.name) }

    /// brew would refuse: something not selected still needs a selected formula. brew checks
    /// every formula before removing any, so then it removes none of them.
    var isBlocked: Bool { !blockers.isEmpty }

    /// The selection plus everything that needs it, added until nothing left over needs any
    /// of it, so brew has nothing to refuse
    func includingDependents(in installed: [InstalledPackage]) -> UninstallPlan {
        var plan = self
        while plan.isBlocked {
            plan = UninstallPlan(packages: plan.packages + plan.blockingPackages, installed: installed)
        }
        return plan
    }

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

    /// Text for the dialog when brew would refuse. `expanded` is `includingDependents(in:)`.
    func blockedMessage(expanded: UninstallPlan) -> String {
        var parts = blockers.sorted(by: { $0.key < $1.key }).map { name, users in
            "\(users.joined(separator: ", ")) \(users.count == 1 ? "needs" : "need") \(name), so brew won't remove it."
        }
        let added = expanded.names.filter { !names.contains($0) }
        parts.append("To remove \(names.count == 1 ? "it" : "them"), also uninstall \(added.joined(separator: ", ")). "
            + "Otherwise cancel and keep \(names.count == 1 ? names[0] : "them").")
        return parts.joined(separator: "\n\n")
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

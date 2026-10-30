import Foundation

/// An installed formula or cask, built from `brew info --json=v2 --installed`.
struct InstalledPackage: Identifiable, Sendable, Hashable {
    enum Kind: String, Sendable, CaseIterable {
        case formula
        case cask

        var title: String { self == .formula ? "Formula" : "Cask" }
    }

    /// `formula:name` / `cask:token` - a formula and a cask can share a name
    var id: String { "\(kind.rawValue):\(name)" }
    let name: String
    let fullName: String
    let kind: Kind
    let summary: String?
    let homepage: URL?
    let tap: String?
    let installedVersion: String
    let latestVersion: String
    let isOutdated: Bool
    let isPinned: Bool
    /// False for formulae installed only as dependencies of something else
    let installedOnRequest: Bool
    /// When the current version was put in place: an upgrade resets it for formulae;
    /// for casks it's when the cask was first installed
    let installedDate: Date?
    /// Casks that update themselves; `brew outdated` skips these by default
    let autoUpdates: Bool
    /// Full names of every formula this one needs at runtime, directly or not (formulae only)
    var runtimeDependencies: [String] = []
    /// The subset of `runtimeDependencies` the formula declares itself
    var directDependencies: [String] = []
    /// Apps the cask installs, from its current definition (see `CaskApp`)
    var appCandidates: [String] = []
    /// Filled in by `BrewService` after checking the disk
    var appStatus: CaskAppStatus = .notChecked
    /// `brew uninstall` will probably ask for the administrator password (see `CaskApp`)
    var uninstallNeedsAdmin = false
    /// Set when Homebrew has deprecated or disabled the package
    var deprecation: PackageDeprecation?

    /// The app was deleted (or renamed) outside Homebrew; brew's record is all that's left
    var isAppMissing: Bool { appStatus == .missing }

    /// The version actually on disk for casks that update themselves; otherwise brew's record
    var displayedVersion: String {
        if autoUpdates, case .found(let version?, _) = appStatus {
            return version
        }
        return installedVersion
    }

    /// When a self-updating cask's app last updated itself (brew's date is from the
    /// original install and never moves); otherwise brew's `installedDate`
    var displayedInstalledDate: Date? {
        if autoUpdates, case .found(_, let modified?) = appStatus {
            return modified
        }
        return installedDate
    }

    /// The date shown differs from brew's record because the app updated itself
    var hasSelfUpdatedDate: Bool {
        displayedInstalledDate != installedDate
    }

    /// `displayedInstalledDate` for sorting; `Date?` isn't Comparable, so unknown dates sort as oldest
    var installedSortDate: Date { displayedInstalledDate ?? .distantPast }

    /// The latest version without a cask's build number, so it lines up with the installed one
    var displayedLatestVersion: String {
        kind == .cask ? CaskApp.shortVersion(latestVersion) : latestVersion
    }

    /// A self-updating app that hasn't caught up with the latest version yet. The script
    /// can't upgrade these (brew skips them), so they aren't counted as outdated.
    var isSelfUpdateBehind: Bool {
        guard autoUpdates, case .found(let version?, _) = appStatus else { return false }
        return CaskApp.isBehind(appVersion: version, latest: latestVersion)
    }

    /// For each formula, the names of installed formulae that declare it as a direct
    /// dependency, keyed by full name (how `brew info` records dependencies). One pass over
    /// the list, so the table can look it up per row cheaply.
    static func dependents(in installed: [InstalledPackage]) -> [String: [String]] {
        var result: [String: [String]] = [:]
        for package in installed {
            for dependency in package.directDependencies {
                result[dependency, default: []].append(package.name)
            }
        }
        return result.mapValues { $0.sorted { $0.localizedStandardCompare($1) == .orderedAscending } }
    }

    /// Decodes the `brew info --json=v2` document into a single sorted list.
    static func parseBrewInfo(_ data: Data) throws -> [InstalledPackage] {
        let info = try JSONDecoder().decode(BrewInfoDocument.self, from: data)
        let formulae = info.formulae.map { formula in
            let installed = formula.installed.last
            return InstalledPackage(
                name: formula.name,
                fullName: formula.fullName,
                kind: .formula,
                summary: formula.desc,
                homepage: formula.homepage.flatMap(URL.init(string:)),
                tap: formula.tap,
                installedVersion: installed?.version ?? "?",
                latestVersion: formula.versions.stable ?? installed?.version ?? "?",
                isOutdated: formula.outdated,
                isPinned: formula.pinned,
                installedOnRequest: installed?.installedOnRequest ?? true,
                installedDate: installed?.time.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                autoUpdates: false,
                runtimeDependencies: installed?.runtimeDependencies?.map(\.fullName) ?? [],
                directDependencies: installed?.runtimeDependencies?.filter { $0.declaredDirectly == true }.map(\.fullName) ?? [],
                deprecation: formula.lifecycle.deprecation
            )
        }
        let casks = info.casks.map { cask in
            InstalledPackage(
                name: cask.token,
                fullName: cask.fullToken,
                kind: .cask,
                summary: cask.desc ?? cask.name.first,
                homepage: cask.homepage.flatMap(URL.init(string:)),
                tap: cask.tap,
                installedVersion: cask.installed ?? "?",
                latestVersion: cask.version,
                isOutdated: cask.outdated,
                isPinned: false,
                installedOnRequest: true,
                installedDate: cask.installedTime.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                autoUpdates: cask.autoUpdates ?? false,
                appCandidates: CaskApp.appCandidates(fromArtifacts: cask.artifacts ?? []),
                uninstallNeedsAdmin: CaskApp.uninstallNeedsAdmin(artifacts: cask.artifacts ?? []),
                deprecation: cask.lifecycle.deprecation
            )
        }
        return (formulae + casks).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

// MARK: - brew info JSON (only the fields the app uses)

private struct BrewInfoDocument: Decodable {
    let formulae: [Formula]
    let casks: [Cask]

    struct Formula: Decodable {
        struct Versions: Decodable {
            let stable: String?
        }

        struct Dependency: Decodable {
            let fullName: String
            /// False for dependencies of dependencies
            let declaredDirectly: Bool?

            enum CodingKeys: String, CodingKey {
                case fullName = "full_name"
                case declaredDirectly = "declared_directly"
            }
        }

        struct Installed: Decodable {
            let version: String
            let installedOnRequest: Bool?
            let time: Int?
            let runtimeDependencies: [Dependency]?

            enum CodingKeys: String, CodingKey {
                case version
                case installedOnRequest = "installed_on_request"
                case time
                case runtimeDependencies = "runtime_dependencies"
            }
        }

        let name: String
        let fullName: String
        let desc: String?
        let homepage: String?
        let tap: String?
        let versions: Versions
        let installed: [Installed]
        let outdated: Bool
        let pinned: Bool
        let lifecycle: Lifecycle

        enum CodingKeys: String, CodingKey {
            case name
            case fullName = "full_name"
            case desc, homepage, tap, versions, installed, outdated, pinned
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            fullName = try container.decode(String.self, forKey: .fullName)
            desc = try container.decodeIfPresent(String.self, forKey: .desc)
            homepage = try container.decodeIfPresent(String.self, forKey: .homepage)
            tap = try container.decodeIfPresent(String.self, forKey: .tap)
            versions = try container.decode(Versions.self, forKey: .versions)
            installed = try container.decode([Installed].self, forKey: .installed)
            outdated = try container.decode(Bool.self, forKey: .outdated)
            pinned = try container.decode(Bool.self, forKey: .pinned)
            // The deprecation keys sit next to the others, so decode them from the same object
            lifecycle = try Lifecycle(from: decoder)
        }
    }

    struct Cask: Decodable {
        let token: String
        let fullToken: String
        let name: [String]
        let desc: String?
        let homepage: String?
        let tap: String?
        let version: String
        let installed: String?
        let installedTime: Int?
        let outdated: Bool
        let autoUpdates: Bool?
        let artifacts: [JSONValue]?
        let lifecycle: Lifecycle

        enum CodingKeys: String, CodingKey {
            case token
            case fullToken = "full_token"
            case name, desc, homepage, tap, version, installed
            case installedTime = "installed_time"
            case outdated
            case autoUpdates = "auto_updates"
            case artifacts
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            token = try container.decode(String.self, forKey: .token)
            fullToken = try container.decode(String.self, forKey: .fullToken)
            name = try container.decode([String].self, forKey: .name)
            desc = try container.decodeIfPresent(String.self, forKey: .desc)
            homepage = try container.decodeIfPresent(String.self, forKey: .homepage)
            tap = try container.decodeIfPresent(String.self, forKey: .tap)
            version = try container.decode(String.self, forKey: .version)
            installed = try container.decodeIfPresent(String.self, forKey: .installed)
            installedTime = try container.decodeIfPresent(Int.self, forKey: .installedTime)
            outdated = try container.decode(Bool.self, forKey: .outdated)
            autoUpdates = try container.decodeIfPresent(Bool.self, forKey: .autoUpdates)
            artifacts = try container.decodeIfPresent([JSONValue].self, forKey: .artifacts)
            lifecycle = try Lifecycle(from: decoder)
        }
    }

    /// `deprecated` / `disabled` and their details, the same keys for formulae and casks
    struct Lifecycle: Decodable {
        let deprecated: Bool?
        let deprecationDate: String?
        let deprecationReason: String?
        let deprecationReplacementFormula: String?
        let deprecationReplacementCask: String?
        let disabled: Bool?
        let disableDate: String?
        let disableReason: String?
        let disableReplacementFormula: String?
        let disableReplacementCask: String?

        enum CodingKeys: String, CodingKey {
            case deprecated, disabled
            case deprecationDate = "deprecation_date"
            case deprecationReason = "deprecation_reason"
            case deprecationReplacementFormula = "deprecation_replacement_formula"
            case deprecationReplacementCask = "deprecation_replacement_cask"
            case disableDate = "disable_date"
            case disableReason = "disable_reason"
            case disableReplacementFormula = "disable_replacement_formula"
            case disableReplacementCask = "disable_replacement_cask"
        }

        /// Disabled wins: its date and reason are the ones that matter now
        var deprecation: PackageDeprecation? {
            if disabled == true {
                return PackageDeprecation(
                    isDisabled: true, date: disableDate, reason: disableReason,
                    replacement: disableReplacementFormula ?? disableReplacementCask
                )
            }
            if deprecated == true {
                return PackageDeprecation(
                    isDisabled: false, date: deprecationDate, reason: deprecationReason,
                    replacement: deprecationReplacementFormula ?? deprecationReplacementCask
                )
            }
            return nil
        }
    }
}

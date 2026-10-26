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
    let installedDate: Date?
    /// Casks that update themselves; `brew outdated` skips these by default
    let autoUpdates: Bool

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
                autoUpdates: false
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
                autoUpdates: cask.autoUpdates ?? false
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

        struct Installed: Decodable {
            let version: String
            let installedOnRequest: Bool?
            let time: Int?

            enum CodingKeys: String, CodingKey {
                case version
                case installedOnRequest = "installed_on_request"
                case time
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

        enum CodingKeys: String, CodingKey {
            case name
            case fullName = "full_name"
            case desc, homepage, tap, versions, installed, outdated, pinned
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

        enum CodingKeys: String, CodingKey {
            case token
            case fullToken = "full_token"
            case name, desc, homepage, tap, version, installed
            case installedTime = "installed_time"
            case outdated
            case autoUpdates = "auto_updates"
        }
    }
}

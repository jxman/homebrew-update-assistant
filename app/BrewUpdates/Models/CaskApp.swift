import Foundation

/// Whether a cask's app is really on disk, and which version it is.
///
/// Homebrew only records the version it installed. Casks marked `auto_updates` update
/// themselves, and `brew outdated` skips them, so that record goes stale: OrbStack can be
/// current while brew still says 2.0.1. The record also survives the app being deleted.
enum CaskAppStatus: Hashable, Sendable {
    /// Formulae, and casks without an app (command-line tools, fonts)
    case notChecked
    /// None of the cask's apps exist any more
    case missing
    /// The version from the app's Info.plist, if it has one, and when that file last
    /// changed: for a self-updating app, when it last updated itself
    case found(version: String?, modified: Date? = nil)
}

extension DoctorIssue {
    /// The app's own check (brew doctor has none): casks whose app was deleted outside
    /// Homebrew, so only brew's record is left. nil when there are none.
    static func missingCaskApps(in installed: [InstalledPackage]) -> DoctorIssue? {
        let missing = installed.filter(\.isAppMissing).map(\.name)
        guard !missing.isEmpty else { return nil }
        return DoctorIssue(
            level: .warning,
            headline: "Some installed casks have no app on disk",
            details: "",
            check: .missingCaskApps,
            items: missing,
            commands: [],
            links: []
        )
    }
}

/// Loosely typed JSON, for brew's `artifacts` lists, whose entries vary in shape.
enum JSONValue: Decodable, Hashable, Sendable {
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
    case other

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            self = .other
        }
    }

    var strings: [String] {
        switch self {
        case .string(let value): [value]
        case .array(let values): values.flatMap(\.strings)
        default: []
        }
    }
}

enum CaskApp {
    /// App names (`Kiro CLI.app`) and app paths (`/Applications/Adobe Acrobat Reader.app`)
    /// a cask installs, from its artifacts (`brew info` or the cask's install receipt).
    /// Pkg-based casks have no `app` artifact, but list the app in `uninstall: delete:`.
    static func appCandidates(fromArtifacts artifacts: [JSONValue]) -> [String] {
        var result: [String] = []
        for case .object(let artifact) in artifacts {
            if case .array(let entries)? = artifact["app"] {
                // ["Source.app", {"target": "Renamed.app"}] installs as the target name
                let targets = entries.compactMap { entry -> String? in
                    if case .object(let options) = entry { return options["target"]?.strings.first }
                    return nil
                }
                result += targets.isEmpty ? entries.flatMap(\.strings) : targets
            }
            if case .array(let steps)? = artifact["uninstall"] {
                for case .object(let step) in steps {
                    result += (step["delete"]?.strings ?? []).filter { $0.hasSuffix(".app") }
                }
            }
        }
        // Remove duplicates, keeping the order
        var seen = Set<String>()
        return result.filter { seen.insert($0).inserted }
    }

    /// Whether uninstalling will probably ask for the administrator password: it forgets
    /// installer receipts (`pkgutil`), removes kernel extensions, or deletes files outside
    /// the home folder and /Applications. Only a hint for the UI; brew decides for real.
    static func uninstallNeedsAdmin(artifacts: [JSONValue]) -> Bool {
        for case .object(let artifact) in artifacts {
            if artifact["pkg"] != nil { return true }
            guard case .array(let steps)? = artifact["uninstall"] else { continue }
            for case .object(let step) in steps {
                if step["pkgutil"] != nil || step["kext"] != nil { return true }
                let paths = (step["delete"]?.strings ?? []) + (step["rmdir"]?.strings ?? [])
                if paths.contains(where: { !$0.hasPrefix("~") && !$0.hasPrefix("/Applications/") }) { return true }
            }
        }
        return false
    }

    /// True when the app's own version is older than the cask's latest. Cask versions often
    /// add a build number after a comma (`2.2.5,21124`); apps report just `2.2.5`.
    static func isBehind(appVersion: String, latest: String) -> Bool {
        appVersion.compare(shortVersion(latest), options: .numeric) == .orderedAscending
    }

    /// A cask version without its build number: `2.2.5,21124` → `2.2.5`
    static func shortVersion(_ version: String) -> String {
        version.split(separator: ",").first.map(String.init) ?? version
    }
}

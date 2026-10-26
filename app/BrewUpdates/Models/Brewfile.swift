import Foundation

/// One line of a Brewfile, e.g. `brew "shellcheck"` or `cask "firefox"`.
struct BrewfileEntry: Hashable, Identifiable, Sendable, Comparable {
    /// The Brewfile keyword: `tap`, `brew`, `cask`, `mas`, `vscode`, `npm`, ...
    let kind: String
    let name: String

    var id: String { "\(kind):\(name)" }

    /// Taps, formulae and casks: the kinds a restore reinstalls
    var isRestorable: Bool { Self.restorableKinds.contains(kind) }

    static let restorableKinds: Set<String> = ["tap", "brew", "cask"]

    /// Display order: Homebrew kinds first, then the rest alphabetically
    private static let kindOrder = ["tap", "brew", "cask", "mas"]

    static func < (lhs: BrewfileEntry, rhs: BrewfileEntry) -> Bool {
        let left = kindOrder.firstIndex(of: lhs.kind) ?? kindOrder.count
        let right = kindOrder.firstIndex(of: rhs.kind) ?? kindOrder.count
        if left != right { return left < right }
        if lhs.kind != rhs.kind { return lhs.kind < rhs.kind }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    static func title(forKind kind: String) -> String {
        switch kind {
        case "tap": "Taps"
        case "brew": "Formulae"
        case "cask": "Casks"
        case "mas": "App Store"
        case "vscode": "VS Code Extensions"
        case "npm": "npm Packages"
        default: kind.capitalized
        }
    }
}

/// Differences between two Brewfiles.
struct BrewfileDiff: Sendable, Equatable {
    /// In the newer Brewfile only
    let added: [BrewfileEntry]
    /// In the older Brewfile only
    let removed: [BrewfileEntry]

    var isEmpty: Bool { added.isEmpty && removed.isEmpty }
}

enum Brewfile {
    /// Reads the entries from Brewfile text (as written by `brew bundle dump`). Comments,
    /// blank lines and options after the name (`, args: [...]`) are ignored.
    static func parse(_ text: String) -> [BrewfileEntry] {
        let entry = #/^\s*([a-z_]+)\s+"([^"]+)"/#
        var entries: [BrewfileEntry] = []
        text.enumerateLines { line, _ in
            if let match = line.firstMatch(of: entry) {
                entries.append(BrewfileEntry(kind: String(match.1), name: String(match.2)))
            }
        }
        return entries
    }

    static func diff(from older: [BrewfileEntry], to newer: [BrewfileEntry]) -> BrewfileDiff {
        let olderSet = Set(older)
        let newerSet = Set(newer)
        return BrewfileDiff(
            added: newerSet.subtracting(olderSet).sorted(),
            removed: olderSet.subtracting(newerSet).sorted()
        )
    }

    /// A Brewfile containing only these entries, for `brew bundle install`. Taps come
    /// first so formulae and casks from them can be found.
    static func text(for entries: [BrewfileEntry]) -> String {
        entries.sorted().map { "\($0.kind) \"\($0.name)\"" }.joined(separator: "\n") + "\n"
    }
}

/// A Brewfile backup the script made before a run: `~/.brew_backups/brew_backup_<RUN_ID>`.
struct Backup: Identifiable, Sendable, Hashable {
    /// The run ID of the run that made it
    let id: String
    let date: Date
    let url: URL
    let size: Int

    /// `brew_backup_20261025_030115` -> run ID, or nil for other files
    static func runID(fromFileName name: String) -> String? {
        name.wholeMatch(of: #/brew_backup_(\d{8}_\d{6})/#).map { String($0.1) }
    }
}

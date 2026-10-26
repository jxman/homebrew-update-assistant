import Foundation

/// A cask that is installed (it has a folder in the Caskroom) but whose definition Homebrew
/// can no longer load, usually because its tap uses something a newer Homebrew removed.
/// Homebrew then leaves it out silently: `brew info --installed` and `brew outdated` skip it,
/// so scheduled runs never upgrade it and it is missing from the Installed view.
struct UnreadableCask: Equatable, Sendable, Identifiable {
    let token: String
    /// From the install receipt, e.g. `terraform-linters/tap`
    var tap: String?
    var version: String?
    /// Homebrew's error, e.g. "Cask 'tflint' is unreadable: undefined local variable..."
    var error: String?

    var id: String { token }

    /// Caskroom folder names that brew didn't return. Hidden folders aren't casks.
    static func tokens(inCaskroom folders: [String], loaded: Set<String>) -> [String] {
        folders.filter { !$0.hasPrefix(".") && !loaded.contains($0) }.sorted()
    }

    /// Reads the tap and version from the Caskroom's `.metadata/INSTALL_RECEIPT.json`
    static func fromReceipt(token: String, data: Data?) -> UnreadableCask {
        struct Receipt: Decodable {
            struct Source: Decodable {
                let tap: String?
                let version: String?
            }
            let source: Source?
        }
        let source = data.flatMap { try? JSONDecoder().decode(Receipt.self, from: $0) }?.source
        return UnreadableCask(token: token, tap: source?.tap, version: source?.version)
    }

    /// The first "Error:" line of `brew info --cask` output, without the prefix
    static func errorLine(in output: String) -> String? {
        output.split(separator: "\n")
            .first { $0.hasPrefix("Error:") }
            .map { $0.dropFirst("Error:".count).trimmingCharacters(in: .whitespaces) }
    }

    /// The tap's GitHub repository, where its maintainers take reports. Taps named `user/name`
    /// live at github.com/user/homebrew-name; official homebrew/ taps aren't a separate project.
    var tapRepository: URL? {
        guard let tap, !tap.hasPrefix("homebrew/") else { return nil }
        let parts = tap.split(separator: "/")
        guard parts.count == 2 else { return nil }
        return URL(string: "https://github.com/\(parts[0])/homebrew-\(parts[1])")
    }
}

extension DoctorIssue {
    /// The app's own check (brew doctor has none): installed casks Homebrew can't read.
    static func unreadableCasks(_ casks: [UnreadableCask]) -> DoctorIssue? {
        guard !casks.isEmpty else { return nil }
        let details = casks.map { cask in
            let origin = [cask.version, cask.tap.map { "from \($0)" }].compactMap { $0 }.joined(separator: ", ")
            return "\(cask.token)\(origin.isEmpty ? "" : " (\(origin))"): \(cask.error ?? "Homebrew couldn't load it")"
        }
        return DoctorIssue(
            level: .warning,
            headline: "Homebrew can't read some installed casks",
            details: details.joined(separator: "\n"),
            check: .unreadableCasks,
            items: casks.map(\.token),
            commands: [],
            links: Array(Set(casks.compactMap(\.tapRepository))).sorted { $0.absoluteString < $1.absoluteString }
        )
    }
}

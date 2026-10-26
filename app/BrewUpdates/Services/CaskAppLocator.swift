import Foundation

/// Finds a cask's app on disk and reads its version (see `CaskAppStatus`).
struct CaskAppLocator: Sendable {
    /// `<brew prefix>/Caskroom`, which holds each cask's install receipt
    let caskroom: URL
    /// Where casks install apps: /Applications, then ~/Applications
    var applicationDirectories: [URL] = [
        URL(filePath: "/Applications"),
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications")
    ]

    func status(for package: InstalledPackage) -> CaskAppStatus {
        guard package.kind == .cask else { return .notChecked }
        // The receipt lists the app as installed, which matters after a rename: kiro-cli was
        // installed as "Amazon Q.app" but its definition now says "Kiro CLI.app"
        let candidates = package.appCandidates + receiptApps(for: package.name)
        guard !candidates.isEmpty else { return .notChecked }

        let existing = candidates.lazy.flatMap(locations(of:)).first {
            FileManager.default.fileExists(atPath: $0.path)
        }
        guard let app = existing else { return .missing }
        return .found(version: version(of: app))
    }

    private func locations(of candidate: String) -> [URL] {
        if candidate.hasPrefix("/") {
            return [URL(filePath: candidate)]
        }
        if candidate.hasPrefix("~/") {
            return [FileManager.default.homeDirectoryForCurrentUser.appending(path: String(candidate.dropFirst(2)))]
        }
        return applicationDirectories.map { $0.appending(path: candidate) }
    }

    private func receiptApps(for token: String) -> [String] {
        let receipt = caskroom.appending(path: "\(token)/.metadata/INSTALL_RECEIPT.json")
        guard let data = try? Data(contentsOf: receipt),
              let decoded = try? JSONDecoder().decode(Receipt.self, from: data) else {
            return []
        }
        return CaskApp.appCandidates(fromArtifacts: decoded.uninstallArtifacts ?? [])
    }

    private func version(of app: URL) -> String? {
        let plist = app.appending(path: "Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }
        return (info["CFBundleShortVersionString"] ?? info["CFBundleVersion"]) as? String
    }

    private struct Receipt: Decodable {
        let uninstallArtifacts: [JSONValue]?

        enum CodingKeys: String, CodingKey {
            case uninstallArtifacts = "uninstall_artifacts"
        }
    }
}

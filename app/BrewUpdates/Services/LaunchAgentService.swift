import Foundation

enum LaunchAgentError: LocalizedError {
    case notInstalled
    case runInProgress
    case reloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            "The LaunchAgent isn't installed. Run scripts/setup.sh in the repo to install it."
        case .runInProgress:
            "An update is running. Reloading the LaunchAgent now would stop a scheduled run, so wait until it finishes."
        case .reloadFailed(let detail):
            "The schedule was saved, but launchd couldn't reload it: \(detail)"
        }
    }
}

/// Changes the LaunchAgent: its schedule and flags (by rewriting the plist) and whether
/// launchd runs it at all.
///
/// launchd reads the plist only when the job is loaded, so every change is followed by
/// `launchctl bootout` + `bootstrap`, the same reload `scripts/setup.sh` does.
struct LaunchAgentService: Sendable {
    let paths: AppPaths

    private var domain: String { "gui/\(getuid())" }
    private var target: String { "\(domain)/\(AppPaths.launchAgentLabel)" }
    private var backupURL: URL { paths.launchAgentPlist.appendingPathExtension("app-backup") }

    /// Writes the draft into the plist and reloads the job if it was loaded.
    /// The previous plist is kept as `<plist>.app-backup`.
    func save(_ draft: ScheduleDraft, isLoaded: Bool) async throws {
        let plistURL = paths.launchAgentPlist
        guard FileManager.default.fileExists(atPath: plistURL.path) else { throw LaunchAgentError.notInstalled }

        let original = try Data(contentsOf: plistURL)
        let updated = try draft.updatedPlist(original)
        try original.write(to: backupURL, options: .atomic)
        try updated.write(to: plistURL, options: .atomic)

        if isLoaded {
            try await reload()
        }
    }

    /// Turning the schedule off uses `launchctl disable`, which survives logging out and
    /// back in; a plain `bootout` would be undone at the next login.
    func setEnabled(_ enabled: Bool) async throws {
        guard FileManager.default.fileExists(atPath: paths.launchAgentPlist.path) else { throw LaunchAgentError.notInstalled }
        if enabled {
            try await launchctl(["enable", target])
            try await reload()
        } else {
            try await launchctl(["disable", target])
            // Fails harmlessly when the job isn't loaded
            _ = try? await launchctl(["bootout", target])
        }
    }

    private func reload() async throws {
        _ = try? await launchctl(["bootout", target])
        // bootout finishes asynchronously, so an immediate bootstrap can fail with
        // "Input/output error"; retry briefly
        var lastError: Error?
        for attempt in 0..<5 {
            if attempt > 0 {
                try await Task.sleep(for: .milliseconds(300))
            }
            do {
                try await launchctl(["bootstrap", domain, paths.launchAgentPlist.path])
                return
            } catch {
                lastError = error
            }
        }
        throw LaunchAgentError.reloadFailed(lastError?.localizedDescription ?? "unknown error")
    }

    @discardableResult
    private func launchctl(_ arguments: [String]) async throws -> ProcessResult {
        try await ProcessRunner.output(URL(filePath: "/bin/launchctl"), arguments: arguments)
    }
}

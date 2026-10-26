import Foundation

/// Facts about the installation: deployed script, LaunchAgent, config and disk space.
struct SystemStatus: Sendable {
    /// Oldest script that writes the summary files the app depends on
    static let minimumScriptVersion = SemanticVersion("2.2.0")!

    let paths: AppPaths

    /// Version reported by `~/bin/brew-updates.command --version`, or nil if it is
    /// missing or too old to support `--version`.
    func deployedScriptVersion() async -> SemanticVersion? {
        guard FileManager.default.fileExists(atPath: paths.deployedScript.path),
              let result = try? await ProcessRunner.run(
                  URL(filePath: "/bin/bash"),
                  arguments: [paths.deployedScript.path, "--version"]
              ),
              result.exitCode == 0 else {
            return nil
        }
        // Output: "brew-updates.command 2.2.0"
        return result.stdoutText.split(separator: " ").last
            .flatMap { SemanticVersion($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    func schedule() async throws -> Schedule {
        try Schedule.parse(plistData: try Data(contentsOf: paths.launchAgentPlist))
    }

    /// Whether launchd currently has the LaunchAgent loaded.
    func isLaunchAgentLoaded() async -> Bool {
        let target = "gui/\(getuid())/\(AppPaths.launchAgentLabel)"
        let result = try? await ProcessRunner.run(URL(filePath: "/bin/launchctl"), arguments: ["print", target])
        return result?.exitCode == 0
    }

    func config() async -> BrewConfig {
        guard let text = try? String(contentsOf: paths.configFile, encoding: .utf8) else { return BrewConfig() }
        return BrewConfig.parse(text)
    }

    /// Free space on the volume holding Homebrew, in bytes.
    func availableDiskSpace(brewExecutable: URL?) -> Int64? {
        let volume = brewExecutable?.deletingLastPathComponent() ?? paths.home
        let values = try? volume.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }
}

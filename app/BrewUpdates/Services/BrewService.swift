import Foundation

enum BrewServiceError: LocalizedError {
    case brewNotFound

    var errorDescription: String? {
        "Homebrew was not found in /opt/homebrew, /usr/local or /home/linuxbrew."
    }
}

/// Read-only Homebrew queries.
///
/// Every command runs with `HOMEBREW_NO_AUTO_UPDATE=1` so that viewing the app never
/// changes Homebrew's state; updating is left to the script.
struct BrewService: Sendable {
    static let candidatePaths = [
        "/opt/homebrew/bin/brew",
        "/usr/local/bin/brew",
        "/home/linuxbrew/.linuxbrew/bin/brew"
    ]

    let executable: URL?

    init(executable: URL? = BrewService.locate()) {
        self.executable = executable
    }

    static func locate() -> URL? {
        candidatePaths
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) })
            .map { URL(filePath: $0) }
    }

    func installedPackages() async throws -> [InstalledPackage] {
        let result = try await run(["info", "--json=v2", "--installed"])
        return try InstalledPackage.parseBrewInfo(result.stdout)
    }

    /// First line of `brew --version`, e.g. "Homebrew 7.0.10"
    func version() async throws -> String {
        let result = try await run(["--version"])
        return result.stdoutText.split(separator: "\n").first.map(String.init) ?? ""
    }

    private func run(_ arguments: [String]) async throws -> ProcessResult {
        guard let executable else { throw BrewServiceError.brewNotFound }
        return try await ProcessRunner.output(executable, arguments: arguments, environment: environment(for: executable))
    }

    private func environment(for executable: URL) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        // Apps launched from Finder get a minimal PATH; brew needs its own bin directory
        let brewBin = executable.deletingLastPathComponent().path
        env["PATH"] = "\(brewBin):/usr/bin:/bin:/usr/sbin:/sbin"
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        env["HOMEBREW_NO_ENV_HINTS"] = "1"
        env["HOMEBREW_NO_COLOR"] = "1"
        return env
    }
}

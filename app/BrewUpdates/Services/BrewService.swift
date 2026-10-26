import Foundation

enum BrewServiceError: LocalizedError {
    case brewNotFound

    var errorDescription: String? {
        "Homebrew was not found in /opt/homebrew, /usr/local or /home/linuxbrew."
    }
}

/// Homebrew queries, plus pin/unpin, uninstalls and Brewfile restores.
///
/// Every command runs with `HOMEBREW_NO_AUTO_UPDATE=1` so that brew never updates itself as
/// a side effect; updating and upgrading are left to the script.
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

    /// The search path the LaunchAgent gives the script (see scripts/setup.sh). Using it
    /// everywhere means brew finds the same tools whether a run starts at 3 AM or from the
    /// app: `brew bundle dump` only lists VS Code extensions when it finds `code`, which lives
    /// in /usr/local/bin. A shorter PATH made backups from the app silently incomplete.
    static func searchPath(brewExecutable: URL?) -> String {
        let prefix = brewExecutable?.deletingLastPathComponent().deletingLastPathComponent().path ?? "/opt/homebrew"
        return "\(prefix)/bin:\(prefix)/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    }

    static func locate() -> URL? {
        candidatePaths
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) })
            .map { URL(filePath: $0) }
    }

    func installedPackages() async throws -> [InstalledPackage] {
        let result = try await run(["info", "--json=v2", "--installed"])
        var packages = try InstalledPackage.parseBrewInfo(result.stdout)
        // brew's record of a cask can be stale (self-updating apps) or outlive the app itself
        let prefix = executable?.deletingLastPathComponent().deletingLastPathComponent() ?? URL(filePath: "/opt/homebrew")
        let locator = CaskAppLocator(caskroom: prefix.appending(path: "Caskroom"))
        for index in packages.indices where packages[index].kind == .cask {
            packages[index].appStatus = locator.status(for: packages[index])
        }
        return packages
    }

    /// First line of `brew --version`, e.g. "Homebrew 7.0.10"
    func version() async throws -> String {
        let result = try await run(["--version"])
        return result.stdoutText.split(separator: "\n").first.map(String.init) ?? ""
    }

    /// What is installed now, in Brewfile form (`brew bundle dump` to stdout)
    func currentBrewfile() async throws -> [BrewfileEntry] {
        Brewfile.parse(try await run(["bundle", "dump", "--file=-"]).stdoutText)
    }

    /// `brew bundle install` with live output. `--no-upgrade` only installs what is missing;
    /// anything already installed is left at its current version.
    func launchBundleInstall(brewfile: URL, askpass: URL?) async throws -> LaunchedProcess {
        guard let executable else { throw BrewServiceError.brewNotFound }
        return try await ProcessStream.launch(
            executable,
            arguments: ["bundle", "install", "--file=\(brewfile.path)", "--no-upgrade"],
            environment: environment(for: executable, askpass: askpass)
        )
    }

    /// Runs `brew doctor --verbose` (read-only). Doctor exits 1 whenever it finds anything, so
    /// the exit code is ignored; its warnings go to stderr and the config sections to stdout.
    func doctor() async throws -> DoctorReport {
        guard let executable else { throw BrewServiceError.brewNotFound }
        let result = try await ProcessRunner.run(executable, arguments: ["doctor", "--verbose"], environment: environment(for: executable))
        return DoctorReport.parse(result.stdoutText + "\n" + result.stderrText)
    }

    /// `brew uninstall` with live output, using the arguments from an `UninstallPlan`.
    func launchUninstall(_ plan: UninstallPlan, askpass: URL?) async throws -> LaunchedProcess {
        guard let executable else { throw BrewServiceError.brewNotFound }
        return try await ProcessStream.launch(
            executable,
            arguments: plan.arguments,
            environment: environment(for: executable, askpass: askpass)
        )
    }

    /// `brew pin` / `brew unpin`. Only formulae can be pinned.
    func setPinned(_ pinned: Bool, formulae names: [String]) async throws {
        _ = try await run([pinned ? "pin" : "unpin"] + names)
    }

    private func run(_ arguments: [String]) async throws -> ProcessResult {
        guard let executable else { throw BrewServiceError.brewNotFound }
        return try await ProcessRunner.output(executable, arguments: arguments, environment: environment(for: executable))
    }

    /// `askpass`: a program that shows a password dialog. With it set, brew runs `sudo -A`, so
    /// steps that need the administrator password ask with a dialog instead of failing for
    /// lack of a terminal. brew passes `SUDO_ASKPASS` through its environment filter.
    private func environment(for executable: URL, askpass: URL? = nil) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        if let askpass {
            env["SUDO_ASKPASS"] = askpass.path
        }
        // Apps launched from Finder get a minimal PATH
        env["PATH"] = Self.searchPath(brewExecutable: executable)
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        env["HOMEBREW_NO_ENV_HINTS"] = "1"
        env["HOMEBREW_NO_COLOR"] = "1"
        return env
    }
}

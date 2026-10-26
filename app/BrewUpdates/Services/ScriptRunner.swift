import Foundation

/// Runs the deployed `~/bin/brew-updates.command` with live output.
struct ScriptRunner: Sendable {
    let paths: AppPaths
    let brewExecutable: URL?

    func launch(_ action: ScriptAction) async throws -> LaunchedProcess {
        // The LaunchAgent also runs the script with macOS /bin/bash
        try await ProcessStream.launch(
            URL(filePath: "/bin/bash"),
            arguments: [paths.deployedScript.path] + action.arguments,
            environment: environment()
        )
    }

    private func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        // Apps launched from Finder get a minimal PATH; the script finds brew, grype and the
        // tools `brew bundle dump` uses on PATH
        env["PATH"] = BrewService.searchPath(brewExecutable: brewExecutable)
        // Labels the run in its summary (`trigger: "app"`)
        env["BREW_UPDATE_TRIGGER"] = "app"
        env["NO_COLOR"] = "1"
        env["HOMEBREW_NO_COLOR"] = "1"
        env["HOMEBREW_NO_ENV_HINTS"] = "1"
        return env
    }
}

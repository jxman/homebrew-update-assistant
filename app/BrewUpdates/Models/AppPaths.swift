import Foundation

/// File locations shared with `brew-updates.command`.
///
/// Everything hangs off `home` so tests can point the app at a fixture directory
/// instead of the real `~/.brew_logs`.
struct AppPaths: Sendable {
    static let launchAgentLabel = "com.user.brew-update"
    static let current = AppPaths(home: FileManager.default.homeDirectoryForCurrentUser)

    let home: URL

    var logDirectory: URL { home.appending(path: ".brew_logs", directoryHint: .isDirectory) }
    var backupDirectory: URL { home.appending(path: ".brew_backups", directoryHint: .isDirectory) }
    var lockPIDFile: URL { logDirectory.appending(path: ".brew-updates.lock/pid") }
    var configFile: URL { home.appending(path: ".brew_update_config") }
    var deployedScript: URL { home.appending(path: "bin/brew-updates.command") }
    var launchAgentPlist: URL {
        home.appending(path: "Library/LaunchAgents/\(Self.launchAgentLabel).plist")
    }
    var launchAgentLog: URL { logDirectory.appending(path: "launchagent.log") }
    var launchAgentErrorLog: URL { logDirectory.appending(path: "launchagent_error.log") }
    /// Written by the app with its own location; the script makes notifications open the
    /// app (instead of the log folder) when this points at an existing app
    var appMarker: URL { logDirectory.appending(path: ".brew-updates-app") }
}

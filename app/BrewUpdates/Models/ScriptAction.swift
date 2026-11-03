import Foundation

/// Something the app asks the deployed script to do.
enum ScriptAction: Sendable, Equatable {
    /// Upgrade everything outdated, like the scheduled run
    case update
    /// Refresh Homebrew's package index, then show what would be upgraded (`--check`).
    /// No installed package changes.
    case check
    /// Upgrade only these packages (`--packages`)
    case upgrade(packages: [String])

    var title: String {
        switch self {
        case .update: "Update All"
        case .check: "Check for Updates"
        case .upgrade(let packages): packages.count == 1 ? "Upgrade \(packages[0])" : "Upgrade \(packages.count) Packages"
        }
    }

    var systemImage: String {
        switch self {
        case .update: "arrow.down.circle"
        case .check: "magnifyingglass"
        case .upgrade: "arrow.up.circle"
        }
    }

    /// A check only refreshes the index and reports, so it starts without asking for confirmation
    var changesSystem: Bool { self != .check }

    /// `--yes` because there is no terminal to answer prompts, `--no-color` because the
    /// output is shown as plain text.
    var arguments: [String] {
        var arguments = ["--yes", "--no-color"]
        switch self {
        case .update:
            break
        case .check:
            arguments.append("--check")
        case .upgrade(let packages):
            arguments += ["--packages", packages.joined(separator: " ")]
        }
        return arguments
    }
}

/// How a script run ended, from its exit code (see EXIT CODES in `--help`).
enum ScriptOutcome: Sendable, Equatable {
    case success
    case generalError
    case networkError
    case diskSpaceError
    case homebrewError
    case alreadyRunning
    case cancelled
    case other(Int32)

    init(exitCode: Int32) {
        switch exitCode {
        case 0: self = .success
        case 1: self = .generalError
        case 2: self = .networkError
        case 3: self = .diskSpaceError
        case 4: self = .homebrewError
        case 5: self = .alreadyRunning
        // 130 = SIGINT, 143 = SIGTERM; the script turns both into normal exits
        case 130, 143: self = .cancelled
        default: self = .other(exitCode)
        }
    }

    var message: String {
        switch self {
        case .success: "Finished successfully"
        case .generalError: "Finished with errors"
        case .networkError: "Failed: network error"
        case .diskSpaceError: "Failed: not enough disk space"
        case .homebrewError: "Failed: Homebrew error"
        case .alreadyRunning: "Another update is already running"
        case .cancelled: "Stopped"
        case .other(let code): "Exited with code \(code)"
        }
    }
}

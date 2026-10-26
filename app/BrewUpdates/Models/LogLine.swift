import Foundation

/// Log levels written by the script's `log_message` (`[timestamp] [LEVEL] message`).
/// `output` covers lines without that prefix, e.g. raw `brew upgrade` output.
enum LogLevel: String, CaseIterable, Sendable, Identifiable {
    case error = "ERROR"
    case warning = "WARNING"
    case success = "SUCCESS"
    case info = "INFO"
    case verbose = "VERBOSE"
    case output = "OUTPUT"

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct LogLine: Identifiable, Sendable, Equatable {
    /// Line number, which also makes a stable identity for SwiftUI lists
    let id: Int
    let timestamp: String?
    let level: LogLevel
    let message: String

    /// Splits log text into lines and pulls out the timestamp and level where present.
    /// ANSI color codes (present in launchagent.log) are stripped.
    static func parse(_ text: String) -> [LogLine] {
        let prefix = #/^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] \[([A-Z]+)\] ?(.*)$/#
        let ansi = #/\u{1B}\[[0-9;]*[A-Za-z]/#

        var lines: [LogLine] = []
        var number = 0
        text.enumerateLines { rawLine, _ in
            number += 1
            let line = rawLine.replacing(ansi, with: "")
            if let match = line.wholeMatch(of: prefix) {
                let level = LogLevel(rawValue: String(match.2)) ?? .output
                lines.append(LogLine(id: number, timestamp: String(match.1), level: level, message: String(match.3)))
            } else {
                lines.append(LogLine(id: number, timestamp: nil, level: .output, message: line))
            }
        }
        return lines
    }
}

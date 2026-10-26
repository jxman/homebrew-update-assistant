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
    static func parse(_ text: String) -> [LogLine] {
        var lines: [LogLine] = []
        text.enumerateLines { line, _ in
            lines.append(parse(line: line, number: lines.count + 1))
        }
        return lines
    }

    /// Parses a single line, e.g. one streamed from a run in progress. `number` becomes its id.
    /// ANSI color codes (present in launchagent.log) are stripped.
    static func parse(line rawLine: String, number: Int) -> LogLine {
        let prefix = #/^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] \[([A-Z]+)\] ?(.*)$/#
        let ansi = #/\u{1B}\[[0-9;]*[A-Za-z]/#

        let line = rawLine.replacing(ansi, with: "")
        guard let match = line.wholeMatch(of: prefix) else {
            return LogLine(id: number, timestamp: nil, level: .output, message: line)
        }
        let level = LogLevel(rawValue: String(match.2)) ?? .output
        return LogLine(id: number, timestamp: String(match.1), level: level, message: String(match.3))
    }
}

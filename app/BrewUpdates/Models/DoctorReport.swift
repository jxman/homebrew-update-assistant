import Foundation

/// A suggested fix: what it does, and the command to run (if it is one).
struct DoctorFix: Identifiable, Hashable, Sendable {
    var id: String { "\(title)|\(command ?? "")" }
    let title: String
    var command: String?

    /// Contains a placeholder such as `<user>/<tap>` that must be filled in before running
    var isTemplate: Bool {
        command?.contains(#/<[^>]+>/#) == true
    }
}

/// One warning (or error) from `brew doctor`.
struct DoctorIssue: Identifiable, Hashable, Sendable {
    enum Level: Sendable { case warning, error }

    /// Stable across runs, so the same problem can be tracked over time. Known checks use the
    /// check name, because some headlines contain details that change (e.g. a macOS version).
    var id: String { check == .unknown ? headline : check.rawValue }
    let level: Level
    /// First sentence, e.g. "Some installed kegs have no formulae!"
    let headline: String
    /// Everything brew doctor printed after the headline
    let details: String
    let check: DoctorCheck
    /// Packages, taps or paths listed in the warning
    let items: [String]
    /// Commands brew doctor itself suggests, captioned with the sentence that introduced them
    let commands: [DoctorFix]
    let links: [URL]

    var importance: DoctorImportance {
        level == .error ? .important : check.importance
    }
}

/// A parsed `brew doctor --verbose` report (the script's `*.doctor.log`, or a check run from the app).
struct DoctorReport: Equatable, Sendable {
    var issues: [DoctorIssue] = []
    var homebrewVersion: String?
    var macOSVersion: String?
    /// "This is a Tier 2 configuration" -> "Tier 2"; nil for a fully supported (Tier 1) setup
    var supportTier: String?

    /// Commands found in doctor's text. Lines in a warning that start with one of these are
    /// treated as commands to suggest; other indented single words are affected items.
    static let commandTools: Set<String> = [
        "brew", "sudo", "git", "xcode-select", "xcodebuild", "softwareupdate", "rm", "mkdir",
        "chmod", "chown", "echo", "export", "eval", "ln", "mv"
    ]

    /// Commands doctor mentions inline in backticks that are complete without arguments
    private static let completeInlineCommands: Set<String> = [
        "brew cleanup", "brew missing", "brew update", "brew update-reset"
    ]

    static func parse(_ text: String) -> DoctorReport {
        let ansi = #/\u{1B}\[[0-9;]*[A-Za-z]/#
        let lines = text.replacing(ansi, with: "").components(separatedBy: .newlines)

        var report = DoctorReport()
        var current: PendingIssue?
        // The --verbose config sections ("==> macOS" followed by "27.0.1")
        var section: String?

        // A nested function can change the local variables around it
        func finishIssue() {
            if let current {
                report.issues.append(current.issue())
            }
            current = nil
        }

        for line in lines {
            if let match = line.wholeMatch(of: #/(Warning|Error): (.*)/#) {
                finishIssue()
                current = PendingIssue(level: match.1 == "Error" ? .error : .warning, headline: String(match.2))
            } else if line.hasPrefix("==> ") {
                finishIssue()
                section = String(line.dropFirst(4))
            } else if line == "Your system is ready to brew." {
                finishIssue()
            } else if let tier = line.firstMatch(of: #/^This is an? (.+) configuration:/#) {
                finishIssue()
                report.supportTier = String(tier.1)
            } else if current != nil {
                current?.body.append(line)
            } else {
                report.recordConfig(line, section: section)
            }
        }
        finishIssue()
        return report
    }

    /// Picks the versions out of the --verbose config sections; other sections are ignored.
    private mutating func recordConfig(_ line: String, section: String?) {
        let value = line.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return }
        if section == "Homebrew Version", homebrewVersion == nil {
            homebrewVersion = value
        } else if section == "macOS", macOSVersion == nil {
            macOSVersion = value
        }
    }

    /// The lines of one warning, collected until the next one starts.
    private struct PendingIssue {
        let level: DoctorIssue.Level
        var headline: String
        var body: [String] = []

        func issue() -> DoctorIssue {
            var headline = headline
            var body = body
            // Some headlines wrap onto the next line ("...was not found in your PATH but you have installed")
            while let last = headline.last, !".!?:".contains(last),
                  let next = body.first, !next.isEmpty, next.first?.isWhitespace == false {
                headline += " " + next
                body.removeFirst()
            }

            var content = IssueContent()
            // The headline can mention a command too ("Remove them with `brew cleanup`")
            for line in [headline] + body {
                content.add(line)
            }
            return DoctorIssue(
                level: level,
                headline: headline,
                details: body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
                check: DoctorCheck(headline: headline),
                items: content.items,
                commands: content.commands,
                links: content.links
            )
        }
    }

    /// Sorts a warning's lines into affected items, suggested commands and links.
    private struct IssueContent {
        var items: [String] = []
        var commands: [DoctorFix] = []
        var links: [URL] = []
        /// The last unindented sentence, used as the caption of the commands under it
        private var caption: String?

        mutating func add(_ line: String) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return }

            for match in trimmed.matches(of: #/https?://[^\s)]+/#) {
                if let url = URL(string: String(match.0)), !links.contains(url) {
                    links.append(url)
                }
            }
            if trimmed.hasPrefix("http") { return }

            if line.first?.isWhitespace == false {
                addSentence(trimmed)
            } else if DoctorReport.isCommand(trimmed) {
                commands.append(DoctorFix(title: caption ?? "Suggested by brew doctor", command: trimmed))
            } else if !trimmed.contains(" "), !items.contains(trimmed) {
                items.append(trimmed)
            }
        }

        private mutating func addSentence(_ text: String) {
            // Only the last sentence: "...from the listed taps. Trust whole taps with:" -> "Trust whole taps with"
            let sentence = text.components(separatedBy: ". ").last ?? text
            caption = sentence.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            for match in text.matches(of: #/`([^`]+)`/#) {
                let command = String(match.1)
                if DoctorReport.isInlineCommandComplete(command) {
                    commands.append(DoctorFix(title: caption ?? command, command: command))
                }
            }
        }
    }

    private static func isCommand(_ text: String) -> Bool {
        let words = text.split(separator: " ")
        guard words.count > 1, let tool = words.first else { return false }
        return commandTools.contains(String(tool))
    }

    /// `brew untap` alone is only half a command (the taps are listed separately), but
    /// `brew cleanup` or `sudo xcodebuild -license accept` can be run as they are.
    private static func isInlineCommandComplete(_ text: String) -> Bool {
        guard isCommand(text) else { return false }
        return completeInlineCommands.contains(text) || text.split(separator: " ").count > 2
    }
}

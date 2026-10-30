import Foundation

/// `~/.brew_update_config`, parsed with the same rules as the script's `load_config`:
/// `KEY=value`, `#` comments, optional quotes and trailing ` # comment`.
struct BrewConfig: Sendable, Equatable {
    var values: [String: String] = [:]

    var excludedFormulae: Set<String> { words(for: "EXCLUDED_FORMULAE") }
    var excludedCasks: Set<String> { words(for: "EXCLUDED_CASKS") }

    /// On unless set to false (the script's default since 2.4.0)
    var securityScanEnabled: Bool { values["SECURITY_SCAN_ENABLED"] != "false" }

    /// Lowest severities the script shows in its logs (default HIGH,CRITICAL, like the script)
    var securitySeverities: Set<Severity> {
        let raw = values["SECURITY_SCAN_SEVERITY"] ?? "HIGH,CRITICAL"
        return Set(raw.split(separator: ",").map { Severity(grype: String($0)) })
    }

    func isExcluded(_ package: InstalledPackage) -> Bool {
        let excluded = package.kind == .formula ? excludedFormulae : excludedCasks
        return excluded.contains(package.name) || excluded.contains(package.fullName)
    }

    private func words(for key: String) -> Set<String> {
        Set(wordList(for: key))
    }

    private func wordList(for key: String) -> [String] {
        (values[key] ?? "").split(whereSeparator: \.isWhitespace).map(String.init)
    }

    static func parse(_ text: String) -> BrewConfig {
        var config = BrewConfig()
        text.enumerateLines { line, _ in
            guard let (key, rawValue) = assignment(in: line) else { return }
            config.values[key] = normalize(rawValue)
        }
        return config
    }

    /// `KEY` and the raw text after `=`, or nil for comments and other lines.
    private static func assignment(in line: String) -> (key: String, rawValue: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix("#"), let separator = trimmed.firstIndex(of: "=") else { return nil }
        let key = trimmed[..<separator].trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return nil }
        return (key, String(trimmed[trimmed.index(after: separator)...]))
    }

    /// Drops a trailing ` # comment`, trims, and strips one pair of matching quotes.
    static func normalize(_ raw: String) -> String {
        var value = raw
        if let comment = value.firstMatch(of: #/\s+#/#) {
            value = String(value[..<comment.range.lowerBound])
        }
        value = value.trimmingCharacters(in: .whitespaces)
        if value.count >= 2, let first = value.first, first == value.last, first == "\"" || first == "'" {
            value = String(value.dropFirst().dropLast())
        }
        return value
    }

    // MARK: Editing

    /// Names the script accepts in `EXCLUDED_FORMULAE` / `EXCLUDED_CASKS`. One bad name makes
    /// it ignore the whole list, so the app refuses to write anything else.
    static func isValidExclusionName(_ name: String) -> Bool {
        name.wholeMatch(of: #/[a-zA-Z0-9@._\/-]+/#) != nil
    }

    static func exclusionKey(for kind: InstalledPackage.Kind) -> String {
        kind == .formula ? "EXCLUDED_FORMULAE" : "EXCLUDED_CASKS"
    }

    /// Returns `text` with the packages added to or removed from their exclusion lists.
    static func settingExclusion(_ excluded: Bool, for packages: [InstalledPackage], in text: String) throws -> String {
        let config = parse(text)
        var result = text
        for kind in InstalledPackage.Kind.allCases {
            let matching = packages.filter { $0.kind == kind }
            guard !matching.isEmpty else { continue }
            let key = exclusionKey(for: kind)
            var list = config.wordList(for: key)
            for package in matching {
                if excluded {
                    guard !list.contains(package.name), !list.contains(package.fullName) else { continue }
                    guard isValidExclusionName(package.name) else { throw ConfigEditError.unsupportedName(package.name) }
                    list.append(package.name)
                } else {
                    list.removeAll { $0 == package.name || $0 == package.fullName }
                }
            }
            result = setting(key, to: list.joined(separator: " "), in: result)
        }
        return result
    }

    /// Replaces the last `KEY=` line (the script lets later lines win), keeping any trailing
    /// comment, or appends a new line when the key is missing.
    static func setting(_ key: String, to value: String, in text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        let newLine = "\(key)=\"\(value)\""
        if let index = lines.lastIndex(where: { assignment(in: $0)?.key == key }) {
            let comment = lines[index].firstMatch(of: #/\s+#.*$/#).map { String($0.output) } ?? ""
            lines[index] = newLine + comment
        } else if lines.last == "" {
            // Keep the file's final newline after the appended line
            lines.insert(newLine, at: lines.count - 1)
        } else {
            lines.append(newLine)
        }
        return lines.joined(separator: "\n")
    }
}

enum ConfigEditError: LocalizedError {
    case unsupportedName(String)
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedName(let name):
            "\"\(name)\" can't be added to the exclusion list; the script only accepts letters, digits and @ . _ / -"
        case .unreadable(let detail):
            "Couldn't read ~/.brew_update_config: \(detail)"
        }
    }
}

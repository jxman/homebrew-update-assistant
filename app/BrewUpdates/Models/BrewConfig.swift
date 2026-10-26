import Foundation

/// Read-only view of `~/.brew_update_config`, parsed with the same rules as the script's
/// `load_config`: `KEY=value`, `#` comments, optional quotes and trailing ` # comment`.
struct BrewConfig: Sendable, Equatable {
    var values: [String: String] = [:]

    var excludedFormulae: Set<String> { words(for: "EXCLUDED_FORMULAE") }
    var excludedCasks: Set<String> { words(for: "EXCLUDED_CASKS") }

    var securityScanEnabled: Bool { values["SECURITY_SCAN_ENABLED"] == "true" }

    /// Severities the script is configured to report (default HIGH,CRITICAL, like the script)
    var securitySeverities: Set<Severity> {
        let raw = values["SECURITY_SCAN_SEVERITY"] ?? "HIGH,CRITICAL"
        return Set(raw.split(separator: ",").map { Severity(grype: String($0)) })
    }

    func isExcluded(_ package: InstalledPackage) -> Bool {
        let excluded = package.kind == .formula ? excludedFormulae : excludedCasks
        return excluded.contains(package.name) || excluded.contains(package.fullName)
    }

    private func words(for key: String) -> Set<String> {
        Set((values[key] ?? "").split(whereSeparator: \.isWhitespace).map(String.init))
    }

    static func parse(_ text: String) -> BrewConfig {
        var config = BrewConfig()
        text.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), let separator = trimmed.firstIndex(of: "=") else { return }
            let key = trimmed[..<separator].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { return }
            config.values[key] = normalize(String(trimmed[trimmed.index(after: separator)...]))
        }
        return config
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
}

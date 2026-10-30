import Foundation

/// An editable copy of the settings in `~/.brew_update_config`.
///
/// Missing or invalid values fall back to the script's defaults, the same way `load_config`
/// ignores a value that fails validation.
struct ConfigDraft: Sendable, Equatable {
    /// Severities the script's SECURITY_SCAN_SEVERITY accepts, most severe first
    static let scanSeverities: [Severity] = [.critical, .high, .medium, .low]

    var maxBackupCount = 5
    var logRetentionDays = 30
    var skipCasksByDefault = false
    var cleanupByDefault = true
    var notificationsEnabled = false
    var securityScanEnabled = true
    var vulnsScanEnabled = true
    var securitySeverities: Set<Severity> = [.high, .critical]
    var excludedFormulae: [String] = []
    var excludedCasks: [String] = []

    init() {}

    init(config: BrewConfig) {
        let values = config.values
        maxBackupCount = values["MAX_BACKUP_COUNT"].flatMap(Self.count) ?? maxBackupCount
        logRetentionDays = values["LOG_RETENTION_DAYS"].flatMap(Self.count) ?? logRetentionDays
        skipCasksByDefault = values["SKIP_CASKS_BY_DEFAULT"].flatMap(Self.bool) ?? skipCasksByDefault
        cleanupByDefault = values["CLEANUP_BY_DEFAULT"].flatMap(Self.bool) ?? cleanupByDefault
        notificationsEnabled = values["ENABLE_NOTIFICATIONS"].flatMap(Self.bool) ?? notificationsEnabled
        securityScanEnabled = values["SECURITY_SCAN_ENABLED"].flatMap(Self.bool) ?? securityScanEnabled
        vulnsScanEnabled = values["VULNS_SCAN_ENABLED"].flatMap(Self.bool) ?? vulnsScanEnabled
        let severityList = #/(LOW|MEDIUM|HIGH|CRITICAL)(,(LOW|MEDIUM|HIGH|CRITICAL))*/#
        if let raw = values["SECURITY_SCAN_SEVERITY"], raw.wholeMatch(of: severityList) != nil {
            securitySeverities = Set(raw.split(separator: ",").map { Severity(grype: String($0)) })
        }
        excludedFormulae = Self.names(values["EXCLUDED_FORMULAE"])
        excludedCasks = Self.names(values["EXCLUDED_CASKS"])
    }

    /// Each setting as the config file stores it. Keys are in display order.
    var fileValues: KeyValuePairs<String, String> {
        [
            "MAX_BACKUP_COUNT": String(maxBackupCount),
            "LOG_RETENTION_DAYS": String(logRetentionDays),
            "SKIP_CASKS_BY_DEFAULT": String(skipCasksByDefault),
            "CLEANUP_BY_DEFAULT": String(cleanupByDefault),
            "ENABLE_NOTIFICATIONS": String(notificationsEnabled),
            "SECURITY_SCAN_ENABLED": String(securityScanEnabled),
            "SECURITY_SCAN_SEVERITY": Self.scanSeverities
                .filter(securitySeverities.contains)
                .map { $0.rawValue.uppercased() }
                .joined(separator: ","),
            "VULNS_SCAN_ENABLED": String(vulnsScanEnabled),
            "EXCLUDED_FORMULAE": excludedFormulae.joined(separator: " "),
            "EXCLUDED_CASKS": excludedCasks.joined(separator: " ")
        ]
    }

    /// Only the settings that differ from `original`, so untouched lines in the file
    /// (including ones the user wrote by hand) stay exactly as they are.
    func changes(from original: ConfigDraft) -> [(key: String, value: String)] {
        let before = Dictionary(uniqueKeysWithValues: original.fileValues.map { ($0.key, $0.value) })
        return fileValues
            .filter { before[$0.key] != $0.value }
            .map { (key: $0.key, value: $0.value) }
    }

    var validationError: String? {
        if maxBackupCount < 1 { return "Keep at least 1 Brewfile backup." }
        if logRetentionDays < 1 { return "Keep logs for at least 1 day." }
        if (securityScanEnabled || vulnsScanEnabled) && securitySeverities.isEmpty { return "Choose at least one severity to report." }
        if let bad = (excludedFormulae + excludedCasks).first(where: { !BrewConfig.isValidExclusionName($0) }) {
            return "\"\(bad)\" isn't a valid package name for the exclusion list."
        }
        return nil
    }

    private static func count(_ text: String) -> Int? {
        text.wholeMatch(of: #/[0-9]+/#) != nil ? Int(text) : nil
    }

    private static func bool(_ text: String) -> Bool? {
        switch text {
        case "true": true
        case "false": false
        default: nil
        }
    }

    private static func names(_ text: String?) -> [String] {
        (text ?? "").split(whereSeparator: \.isWhitespace).map(String.init)
    }
}

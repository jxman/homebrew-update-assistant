import Foundation

/// Writes changes to `~/.brew_update_config`. Only the lines being changed are touched, so
/// the user's comments and other settings stay as they were.
struct ConfigEditor: Sendable {
    let paths: AppPaths

    /// Adds packages to (or removes them from) `EXCLUDED_FORMULAE` / `EXCLUDED_CASKS` and
    /// returns the config as it is now on disk.
    func setExcluded(_ excluded: Bool, for packages: [InstalledPackage]) async throws -> BrewConfig {
        let updated = try BrewConfig.settingExclusion(excluded, for: packages, in: try currentText())
        return try write(updated)
    }

    /// Sets each key (replacing its line, or appending one) and returns the config as it is
    /// now on disk.
    func apply(_ changes: [(key: String, value: String)]) async throws -> BrewConfig {
        var text = try currentText()
        for change in changes {
            text = BrewConfig.setting(change.key, to: change.value, in: text)
        }
        return try write(text)
    }

    private func write(_ text: String) throws -> BrewConfig {
        // `.atomic` writes a temporary file and renames it, so the script never reads a half-written config
        try Data(text.utf8).write(to: paths.configFile, options: .atomic)
        return BrewConfig.parse(text)
    }

    private func currentText() throws -> String {
        guard FileManager.default.fileExists(atPath: paths.configFile.path) else { return "" }
        do {
            return try String(contentsOf: paths.configFile, encoding: .utf8)
        } catch {
            // Never overwrite a config we couldn't read
            throw ConfigEditError.unreadable(error.localizedDescription)
        }
    }
}

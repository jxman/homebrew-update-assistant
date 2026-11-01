import Foundation

/// Reads the Brewfile backups in `~/.brew_backups`.
struct BackupStore: Sendable {
    let paths: AppPaths

    /// Newest first
    func loadBackups() async -> [Backup] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: paths.backupDirectory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls
            .compactMap { url -> Backup? in
                guard let runID = Backup.runID(fromFileName: url.lastPathComponent),
                      let date = RunCatalog.date(fromRunID: runID) else {
                    return nil
                }
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return Backup(id: runID, date: date, url: url, size: size)
            }
            .sorted { $0.id > $1.id }
    }

    func entries(of backup: Backup) async throws -> [BrewfileEntry] {
        Brewfile.parse(try String(contentsOf: backup.url, encoding: .utf8))
    }
}

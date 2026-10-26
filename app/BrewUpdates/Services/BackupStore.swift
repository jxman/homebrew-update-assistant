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

enum RunLockError: LocalizedError {
    case held(pid: Int32?)

    var errorDescription: String? {
        "An update is already running\(pid.map { " (PID \($0))" } ?? ""). Try again when it has finished."
    }

    private var pid: Int32? {
        switch self {
        case .held(let pid): pid
        }
    }
}

/// The script's run lock, `~/.brew_logs/.brew-updates.lock/`, taken by the app for work that
/// mustn't overlap a run (a restore). Same protocol as the script's `acquire_lock`: creating
/// the directory is atomic, and it holds the owner's PID so a stale lock can be detected.
struct RunLock: Sendable {
    let paths: AppPaths

    private var directory: URL { paths.lockPIDFile.deletingLastPathComponent() }

    func acquire() throws {
        try FileManager.default.createDirectory(at: paths.logDirectory, withIntermediateDirectories: true)
        if !makeDirectory() {
            let holder = RunStore.lockHolderPID(paths: paths)
            // Alive holder, or a PID-less lock that's younger than the script's 5-minute grace period
            if holder != nil || !isStalePIDless() {
                throw RunLockError.held(pid: holder)
            }
            try? FileManager.default.removeItem(at: directory)
            guard makeDirectory() else { throw RunLockError.held(pid: nil) }
        }
        try Data("\(getpid())\n".utf8).write(to: paths.lockPIDFile)
    }

    /// Removes the lock, but only if this app still owns it.
    func release() {
        guard let text = try? String(contentsOf: paths.lockPIDFile, encoding: .utf8),
              Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)) == getpid() else {
            return
        }
        try? FileManager.default.removeItem(at: directory)
    }

    /// `mkdir` without `-p`: fails if the directory already exists, which is what makes it a lock
    private func makeDirectory() -> Bool {
        mkdir(directory.path, 0o755) == 0
    }

    private func isStalePIDless() -> Bool {
        if FileManager.default.fileExists(atPath: paths.lockPIDFile.path) {
            // Has a PID, and lockHolderPID found that process dead
            return true
        }
        let created = (try? directory.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
        return Date.now.timeIntervalSince(created) > 5 * 60
    }
}

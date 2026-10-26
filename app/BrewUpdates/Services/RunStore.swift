import Foundation

/// Runs found in the log directory, plus the PID of a run currently holding the lock.
struct RunsSnapshot: Sendable {
    var runs: [Run]
    var runningPID: Int32?
}

/// Reads run history and logs from `~/.brew_logs`.
struct RunStore: Sendable {
    let paths: AppPaths

    func loadRuns() async -> RunsSnapshot {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: paths.logDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        var runs = RunCatalog.groupRuns(fileURLs: urls)
        for index in runs.indices {
            guard let summaryURL = runs[index].files[.summary],
                  let data = try? Data(contentsOf: summaryURL),
                  let summary = try? RunSummary.decode(from: data) else {
                continue
            }
            runs[index].summary = summary
            runs[index].status = summary.runStatus
        }

        // The newest run without a summary is the one in progress while the lock is held
        let runningPID = Self.lockHolderPID(paths: paths)
        if runningPID != nil, let first = runs.first, first.summary == nil {
            runs[0].status = .running
        }
        return RunsSnapshot(runs: runs, runningPID: runningPID)
    }

    /// Reads a log file off the main thread. Large files are read whole; logs are a few
    /// hundred KB at most.
    func readText(at url: URL) async throws -> String {
        let data = try Data(contentsOf: url)
        return String(decoding: data, as: UTF8.self)
    }

    func loadVulnerabilities(at url: URL) async throws -> [Vulnerability] {
        try Vulnerability.parseGrypeReport(try Data(contentsOf: url))
    }

    /// PID from the script's run lock, if that process is still alive.
    static func lockHolderPID(paths: AppPaths) -> Int32? {
        guard let text = try? String(contentsOf: paths.lockPIDFile, encoding: .utf8),
              let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              kill(pid, 0) == 0 else {
            return nil
        }
        return pid
    }
}

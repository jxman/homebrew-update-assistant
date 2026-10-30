import Foundation
import Observation

/// `brew doctor` reports from every run's `*.doctor.log`, plus any check made from the app.
///
/// Its own `@Observable` object, like `LiveRun`, so `AppModel` stays focused on runs and
/// packages. Views reach it as `model.doctor`; SwiftUI tracks properties on nested
/// observable objects just like the model's own.
@MainActor
@Observable
final class DoctorModel {
    /// Newest first
    private(set) var snapshots: [DoctorSnapshot] = []
    /// False until the run logs have been read once, to tell "loading" from "no reports"
    private(set) var hasLoaded = false
    private(set) var isChecking = false
    var checkError: String?

    private let paths: AppPaths
    private let brew: BrewService
    /// Finished runs' logs never change, so each is parsed once
    private var reportCache: [Run.ID: DoctorReport] = [:]
    private var manualCheck: DoctorSnapshot?

    init(paths: AppPaths, brew: BrewService) {
        self.paths = paths
        self.brew = brew
    }

    var latest: DoctorSnapshot? { snapshots.first }

    var histories: [DoctorIssue.ID: DoctorIssueHistory] { DoctorHistory.histories(snapshots) }
    var resolved: [DoctorIssueHistory] { DoctorHistory.resolved(snapshots) }

    /// Rebuilds the list from the runs' doctor logs. A run still in progress may have a
    /// half-written log, so it is skipped until it finishes.
    func reload(runs: [Run]) async {
        let store = RunStore(paths: paths)
        var loaded: [DoctorSnapshot] = []
        for run in runs where run.status != .running {
            guard let url = run.files[.doctor] else { continue }
            var report = reportCache[run.id]
            if report == nil {
                report = try? await store.loadDoctorReport(at: url)
                reportCache[run.id] = report
            }
            if let report {
                loaded.append(DoctorSnapshot(id: run.id, date: run.date, source: .run(run.id), report: report, logURL: url))
            }
        }
        if let manualCheck {
            loaded.append(manualCheck)
        }
        snapshots = loaded.sorted { $0.date > $1.date }
        hasLoaded = true
    }

    /// Runs `brew doctor` now, e.g. to confirm a fix worked, and adds it as the newest report.
    func checkNow(runs: [Run]) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        do {
            let report = try await brew.doctor()
            manualCheck = DoctorSnapshot(id: "manual", date: .now, source: .manual, report: report)
            checkError = nil
            await reload(runs: runs)
        } catch {
            checkError = error.localizedDescription
        }
    }
}

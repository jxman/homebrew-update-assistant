import Foundation
import Observation

/// The app's shared state: everything the screens display, loaded from disk and Homebrew.
///
/// `@Observable` makes SwiftUI track which properties each view reads and re-render only
/// those views when a property changes. `@MainActor` keeps all reads and writes on the main
/// thread, which is where SwiftUI expects UI state to change.
@MainActor
@Observable
final class AppModel {
    enum Section: String, CaseIterable, Identifiable {
        case dashboard
        case installed
        case runs
        case security

        var id: String { rawValue }

        var title: String { rawValue.capitalized }

        /// SF Symbols name for the sidebar icon
        var systemImage: String {
            switch self {
            case .dashboard: "gauge.with.dots.needle.33percent"
            case .installed: "shippingbox"
            case .runs: "clock.arrow.circlepath"
            case .security: "lock.shield"
            }
        }
    }

    // MARK: Navigation

    var selectedSection: Section? = .dashboard
    var selectedRunID: Run.ID?

    // MARK: Loaded data (private(set): only the model changes these)

    private(set) var runs: [Run] = []
    private(set) var runningPID: Int32?
    private(set) var installed: [InstalledPackage] = []
    private(set) var installedError: String?
    private(set) var isLoadingInstalled = false
    private(set) var schedule: Schedule?
    private(set) var scheduleError: String?
    private(set) var isLaunchAgentLoaded: Bool?
    private(set) var scriptVersion: SemanticVersion?
    private(set) var homebrewVersion: String?
    private(set) var config = BrewConfig()
    private(set) var availableDiskSpace: Int64?
    private(set) var lastRefreshed: Date?

    let paths: AppPaths
    private let brew = BrewService()
    private let watcher = DirectoryWatcher()
    private var runsReloadTask: Task<Void, Never>?
    private var hasStarted = false

    init(paths: AppPaths = .current) {
        self.paths = paths
    }

    // MARK: Derived values (computed from the loaded data, so they never go stale)

    var latestRun: Run? { runs.first }
    var latestSummarizedRun: Run? { runs.first { $0.summary != nil } }
    var outdatedPackages: [InstalledPackage] { installed.filter(\.isOutdated) }
    var isRunInProgress: Bool { runningPID != nil }
    var nextScheduledRun: Date? { isLaunchAgentLoaded == false ? nil : schedule?.nextRun(after: .now) }

    var isScriptOutdated: Bool {
        guard let scriptVersion else { return true }
        return scriptVersion < SystemStatus.minimumScriptVersion
    }

    func run(withID id: Run.ID?) -> Run? {
        runs.first { $0.id == id }
    }

    // MARK: Loading

    /// Loads everything once and starts watching the log directory. Safe to call repeatedly.
    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        watcher.start(watching: paths.logDirectory) { [weak self] in
            self?.scheduleRunsReload()
        }
        await refresh()
    }

    /// Reloads all data. The independent loads run in parallel with `async let`.
    func refresh() async {
        let status = SystemStatus(paths: paths)
        let store = RunStore(paths: paths)

        async let snapshot = store.loadRuns()
        async let config = status.config()
        async let scriptVersion = status.deployedScriptVersion()
        async let agentLoaded = status.isLaunchAgentLoaded()
        async let schedule = Result { try await status.schedule() }
        async let homebrewVersion = try? brew.version()
        async let installedLoad: Void = loadInstalled()

        apply(await snapshot)
        self.config = await config
        self.scriptVersion = await scriptVersion
        self.isLaunchAgentLoaded = await agentLoaded
        switch await schedule {
        case .success(let value):
            self.schedule = value
            self.scheduleError = nil
        case .failure(let error):
            self.schedule = nil
            self.scheduleError = error.localizedDescription
        }
        self.homebrewVersion = await homebrewVersion
        self.availableDiskSpace = status.availableDiskSpace(brewExecutable: brew.executable)
        await installedLoad
        lastRefreshed = .now
    }

    func loadInstalled() async {
        isLoadingInstalled = true
        defer { isLoadingInstalled = false }
        do {
            installed = try await brew.installedPackages()
            installedError = nil
        } catch {
            installedError = error.localizedDescription
        }
    }

    func reloadRuns() async {
        apply(await RunStore(paths: paths).loadRuns())
    }

    private func apply(_ snapshot: RunsSnapshot) {
        runs = snapshot.runs
        runningPID = snapshot.runningPID
        if selectedRunID == nil || run(withID: selectedRunID) == nil {
            selectedRunID = runs.first?.id
        }
    }

    /// A run writes several files in quick succession; wait for things to settle so one
    /// burst of file events causes one reload instead of many.
    private func scheduleRunsReload() {
        runsReloadTask?.cancel()
        runsReloadTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await reloadRuns()
        }
    }
}

private extension Result where Failure == Error {
    /// `Result { try await ... }` - capture an async throwing call as a value.
    init(catching body: () async throws -> Success) async {
        do {
            self = .success(try await body())
        } catch {
            self = .failure(error)
        }
    }
}

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

    // MARK: Actions

    /// The run started from the app, kept after it finishes so its output stays viewable
    private(set) var liveRun: LiveRun?
    /// A run waiting for the user to confirm it; `ContentView` shows the dialog
    var pendingAction: ScriptAction?
    /// Shown as an alert when a pin or exclusion change fails
    var actionError: String?
    /// True while a pin/unpin or exclusion change is being written
    private(set) var isChangingPackages = false

    let paths: AppPaths
    /// brew doctor reports and their history
    let doctor: DoctorModel
    /// Scans started from the Security screen
    let security: SecurityScanModel
    private let brew = BrewService()
    private let watcher = DirectoryWatcher()
    private var runsReloadTask: Task<Void, Never>?
    private var liveRunTask: Task<Void, Never>?
    private var periodicRefreshTask: Task<Void, Never>?
    private var hasStarted = false

    init(paths: AppPaths = .current) {
        self.paths = paths
        self.doctor = DoctorModel(paths: paths, brew: BrewService())
        self.security = SecurityScanModel(scanner: SecurityScanner(brewExecutable: BrewService.locate()))
    }

    // MARK: Derived values (computed from the loaded data, so they never go stale)

    var latestRun: Run? { runs.first }
    var latestSummarizedRun: Run? { runs.first { $0.summary != nil } }
    var outdatedPackages: [InstalledPackage] { installed.filter(\.isOutdated) }
    /// A run holds the script's lock (scheduled or from the app), or the app is starting one
    var isRunInProgress: Bool { runningPID != nil || liveRun?.isActive == true }

    /// The last finished run failed or only partly worked (menu bar warning)
    var latestRunNeedsAttention: Bool {
        guard let status = latestSummarizedRun?.status else { return false }
        return status == .failed || status == .partial
    }
    var canStartRun: Bool { !isRunInProgress && !isScriptOutdated }

    /// brew doctor's newest findings (sidebar badge and dashboard)
    var doctorIssues: [DoctorIssue] { doctor.latest?.report.issues ?? [] }
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
        registerAppLocation()
        // Outdated counts change when taps update, so re-check hourly; reading installed
        // packages is local and quick
        periodicRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60 * 60))
                await self?.loadInstalled()
            }
        }
        await refresh()
    }

    /// Lets the script's notifications link to this app (see `AppPaths.appMarker`).
    private func registerAppLocation() {
        try? FileManager.default.createDirectory(at: paths.logDirectory, withIntermediateDirectories: true)
        try? Data((Bundle.main.bundlePath + "\n").utf8).write(to: paths.appMarker, options: .atomic)
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
        await doctor.reload(runs: runs)
        self.config = await config
        self.scriptVersion = await scriptVersion
        self.isLaunchAgentLoaded = await agentLoaded
        applySchedule(await schedule)
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

    /// Re-reads the config file and LaunchAgent, e.g. when the Settings window opens, in
    /// case they were edited by hand.
    func reloadSettings() async {
        let status = SystemStatus(paths: paths)
        config = await status.config()
        isLaunchAgentLoaded = await status.isLaunchAgentLoaded()
        do {
            applySchedule(.success(try await status.schedule()))
        } catch {
            applySchedule(.failure(error))
        }
    }

    private func applySchedule(_ result: Result<Schedule, Error>) {
        switch result {
        case .success(let value):
            schedule = value
            scheduleError = nil
        case .failure(let error):
            schedule = nil
            scheduleError = error.localizedDescription
        }
    }

    func reloadRuns() async {
        apply(await RunStore(paths: paths).loadRuns())
        await doctor.reload(runs: runs)
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
            let previousFinished = latestSummarizedRun?.id
            await reloadRuns()
            // A run finished (e.g. the scheduled one): packages have probably changed
            if latestSummarizedRun?.id != previousFinished {
                await loadInstalled()
            }
        }
    }
}

// MARK: - Actions

extension AppModel {
    /// Starts a dry run straight away; anything that changes the system asks first.
    func request(_ action: ScriptAction) {
        if action.changesSystem {
            pendingAction = action
        } else {
            start(action)
        }
    }

    /// Runs the deployed script and collects its output into `liveRun`.
    func start(_ action: ScriptAction) {
        let runner = ScriptRunner(paths: paths, brewExecutable: brew.executable)
        runLive(title: action.title, systemImage: action.systemImage, writesRunFiles: true) {
            try await runner.launch(action)
        }
    }

    /// Starts a command, shows its output as the live run, and refreshes everything after.
    /// `writesRunFiles`: the script leaves files in ~/.brew_logs to link the live run to.
    /// `finally` runs once the command has exited (or failed to start).
    private func runLive(
        title: String,
        systemImage: String,
        writesRunFiles: Bool,
        finally: (@MainActor () -> Void)? = nil,
        launch: @escaping @Sendable () async throws -> LaunchedProcess
    ) {
        guard canStartRun else { return }
        let run = LiveRun(title: title, systemImage: systemImage)
        liveRun = run
        selectedSection = .runs

        liveRunTask = Task {
            do {
                let launched = try await launch()
                run.state = .running(pid: launched.pid)
                // `for await` receives each event as the script produces it, and ends when the
                // stream finishes after the exit code
                for await event in launched.events {
                    switch event {
                    case .output(let lines):
                        run.append(lines)
                    case .exited(let code):
                        run.state = .finished(ScriptOutcome(exitCode: code))
                    }
                }
            } catch {
                run.state = .failedToStart(error.localizedDescription)
            }
            finally?()
            // Packages and runs have changed; reload them and find this run's files
            await refresh()
            if writesRunFiles {
                run.runID = runs.first { $0.date >= run.startedAt.addingTimeInterval(-2) }?.id
            }
        }
    }

    /// Reinstalls backup entries that are missing now (`brew bundle install --no-upgrade`).
    /// Only taps, formulae and casks; nothing is uninstalled or downgraded. Holds the script's
    /// run lock so a scheduled run can't start partway through.
    func restore(_ entries: [BrewfileEntry], from backup: Backup) {
        let restorable = entries.filter(\.isRestorable)
        guard !restorable.isEmpty, canStartRun else { return }

        let lock = RunLock(paths: paths)
        let brewfile = FileManager.default.temporaryDirectory.appending(path: "BrewUpdates-restore-\(backup.id).Brewfile")
        do {
            try lock.acquire()
            try Brewfile.text(for: restorable).write(to: brewfile, atomically: true, encoding: .utf8)
        } catch {
            lock.release()
            actionError = error.localizedDescription
            return
        }

        let brew = brew
        runLive(
            title: "Restore from \(backup.date.formatted(date: .abbreviated, time: .shortened)) Backup",
            systemImage: "arrow.uturn.backward.circle",
            writesRunFiles: false,
            finally: {
                lock.release()
                try? FileManager.default.removeItem(at: brewfile)
            },
            launch: { try await brew.launchBundleInstall(brewfile: brewfile) }
        )
    }

    /// What is installed now in Brewfile form, for comparing with backups
    func currentBrewfile() async throws -> [BrewfileEntry] {
        try await brew.currentBrewfile()
    }

    /// Shows what a `brewupdates://` link points at.
    func open(_ link: AppLink) {
        switch link {
        case .run(let id):
            selectedRunID = id
            selectedSection = .runs
        case .section(let name):
            if let section = Section(rawValue: name) {
                selectedSection = section
            }
        }
    }

    func stopLiveRun() {
        guard let run = liveRun, case .running(let pid) = run.state else { return }
        run.state = .stopping
        ProcessStream.interrupt(pid: pid)
    }

    /// Waits until the live run has exited, or the timeout passes.
    func waitForLiveRun(timeout: Duration) async {
        let deadline = ContinuousClock.now + timeout
        while liveRun?.isActive == true, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    func setPinned(_ pinned: Bool, for packages: [InstalledPackage]) async {
        let names = packages.filter { $0.kind == .formula && $0.isPinned != pinned }.map(\.name)
        guard !names.isEmpty else { return }
        await changePackages {
            try await brew.setPinned(pinned, formulae: names)
        }
        await loadInstalled()
    }

    func setExcluded(_ excluded: Bool, for packages: [InstalledPackage]) async {
        let editor = ConfigEditor(paths: paths)
        await changePackages {
            config = try await editor.setExcluded(excluded, for: packages)
        }
    }

    // MARK: Settings
    // These throw instead of setting `actionError`, because the Settings window shows
    // errors next to its Save button rather than in the main window.

    func saveSchedule(_ draft: ScheduleDraft) async throws {
        // Reloading the LaunchAgent stops a scheduled run that is in progress
        guard runningPID == nil else { throw LaunchAgentError.runInProgress }
        try await LaunchAgentService(paths: paths).save(draft, isLoaded: isLaunchAgentLoaded == true)
        await reloadSettings()
    }

    func setScheduleEnabled(_ enabled: Bool) async throws {
        guard runningPID == nil else { throw LaunchAgentError.runInProgress }
        // Reload even on failure so the toggle shows launchd's real state
        defer { Task { await reloadSettings() } }
        try await LaunchAgentService(paths: paths).setEnabled(enabled)
    }

    func saveConfig(_ changes: [(key: String, value: String)]) async throws {
        config = try await ConfigEditor(paths: paths).apply(changes)
    }

    private func changePackages(_ change: () async throws -> Void) async {
        isChangingPackages = true
        defer { isChangingPackages = false }
        do {
            try await change()
        } catch {
            actionError = error.localizedDescription
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

import Foundation

// MARK: - brew commands that install or remove packages

extension AppModel {
    /// Reinstalls backup entries that are missing now (`brew bundle install --no-upgrade`).
    /// Only taps, formulae and casks; nothing is uninstalled or downgraded.
    func restore(_ entries: [BrewfileEntry], from backup: Backup) {
        let restorable = entries.filter(\.isRestorable)
        guard !restorable.isEmpty else { return }

        let brewfile = FileManager.default.temporaryDirectory.appending(path: "BrewUpdates-restore-\(backup.id).Brewfile")
        let brew = brew
        runLiveHoldingLock(
            title: "Restore from \(backup.date.formatted(date: .abbreviated, time: .shortened)) Backup",
            systemImage: "arrow.uturn.backward.circle",
            prepare: { try Brewfile.text(for: restorable).write(to: brewfile, atomically: true, encoding: .utf8) },
            cleanup: { try? FileManager.default.removeItem(at: brewfile) },
            launch: { [askpass] in try await brew.launchBundleInstall(brewfile: brewfile, askpass: askpass) }
        )
    }

    /// Checks the packages and asks for confirmation (`InstalledView` shows the dialog).
    func requestUninstall(_ packages: [InstalledPackage]) {
        guard !packages.isEmpty else { return }
        let plan = UninstallPlan(packages: packages, installed: installed)
        if !plan.ambiguousNames.isEmpty {
            actionError = "\(plan.ambiguousNames.joined(separator: ", ")) is installed as both a formula and a cask. "
                + "Uninstall formulae and casks separately."
            return
        }
        pendingUninstall = plan
    }

    /// What uninstalling `plan` really takes: itself, or with everything that needs it
    func uninstallPlanIncludingDependents(_ plan: UninstallPlan) -> UninstallPlan {
        plan.includingDependents(in: installed)
    }

    /// Runs `brew uninstall` with live output. brew itself refuses to remove anything another
    /// installed formula still needs, so no `--ignore-dependencies`.
    func uninstall(_ plan: UninstallPlan) {
        let brew = brew
        let names = plan.names
        runLiveHoldingLock(
            title: "Uninstall \(names.count == 1 ? names[0] : "\(names.count) Packages")",
            systemImage: "trash",
            launch: { [askpass] in try await brew.launchUninstall(plan, askpass: askpass) }
        )
    }

    /// The password dialog bundled in the app (Resources/brew-askpass.sh), for brew's sudo steps
    private var askpass: URL? {
        Bundle.main.url(forResource: "brew-askpass", withExtension: "sh")
    }

    /// `runLive` for brew commands that change what is installed. Holds the script's run lock
    /// so a scheduled run can't start partway through; it is released when the command ends.
    /// `prepare` runs once the lock is held; `cleanup` after the command exits.
    private func runLiveHoldingLock(
        title: String,
        systemImage: String,
        prepare: () throws -> Void = {},
        cleanup: (@MainActor () -> Void)? = nil,
        launch: @escaping @Sendable () async throws -> LaunchedProcess
    ) {
        guard canStartRun else { return }
        let lock = RunLock(paths: paths)
        do {
            try lock.acquire()
            try prepare()
        } catch {
            lock.release()
            actionError = error.localizedDescription
            return
        }
        runLive(
            title: title,
            systemImage: systemImage,
            writesRunFiles: false,
            finally: {
                lock.release()
                cleanup?()
            },
            launch: launch
        )
    }
}

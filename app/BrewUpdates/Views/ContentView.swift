import SwiftUI

/// The main window: a sidebar of sections and the selected section's screen.
struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // `@Bindable` lets us create two-way bindings (`$model.selectedSection`) to an
        // `@Observable` object that came from the environment
        @Bindable var model = model

        NavigationSplitView {
            List(AppModel.Section.allCases, selection: $model.selectedSection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .badge(badgeCount(for: section))
                    .tag(section)
            }
            // `safeAreaInset` pins the footer below the list; the list scrolls above it
            .safeAreaInset(edge: .bottom, spacing: 0) {
                SidebarFooter()
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            VStack(spacing: 0) {
                if model.isScriptOutdated {
                    ScriptOutdatedBanner(version: model.scriptVersion)
                }
                detail(for: model.selectedSection ?? .dashboard)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            // A group so Dry Run and Update All sit side by side as separate buttons
            ToolbarItemGroup {
                RunControl()
            }
            ToolbarItem {
                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Reload runs, packages and settings (⌘R)")
            }
        }
        // `.task` runs async work when the view appears and cancels it if the view goes away
        .task { await model.start() }
        // `brewupdates://` links, e.g. from clicking one of the script's notifications
        .onOpenURL { url in
            if let link = AppLink(url: url) {
                model.open(link)
            }
        }
        // `presenting:` hands the pending action to the dialog's buttons and message. Setting
        // `isPresented` to false (any button does this) clears it again.
        .confirmationDialog(
            model.pendingAction?.title ?? "",
            isPresented: Binding(
                get: { model.pendingAction != nil },
                set: { if !$0 { model.pendingAction = nil } }
            ),
            presenting: model.pendingAction
        ) { action in
            Button(action.title) { model.start(action) }
            Button("Cancel", role: .cancel) {}
        } message: { action in
            Text(confirmationMessage(for: action))
        }
        // Uninstalls are requested from Installed and Doctor, so the dialog lives here
        .confirmationDialog(
            uninstallTitle,
            isPresented: Binding(
                get: { model.pendingUninstall != nil },
                set: { if !$0 { model.pendingUninstall = nil } }
            ),
            presenting: model.pendingUninstall
        ) { plan in
            // `role: .destructive` shows the button in red
            if plan.isBlocked {
                // brew would refuse the selection as it is, so offer only what it will accept
                let expanded = model.uninstallPlanIncludingDependents(plan)
                Button(Self.uninstallButtonTitle(expanded.names), role: .destructive) { model.uninstall(expanded) }
            } else {
                Button(uninstallTitle, role: .destructive) { model.uninstall(plan) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { plan in
            Text(plan.isBlocked ? plan.blockedMessage(expanded: model.uninstallPlanIncludingDependents(plan)) : plan.message)
        }
        .alert(
            "Couldn't change packages",
            isPresented: Binding(
                get: { model.actionError != nil },
                set: { if !$0 { model.actionError = nil } }
            ),
            presenting: model.actionError
        ) { _ in
            Button("OK") {}
        } message: { error in
            Text(error)
        }
    }

    private var uninstallTitle: String {
        guard let plan = model.pendingUninstall else { return "" }
        let names = plan.names
        let subject = names.count == 1 ? names[0] : "\(names.count) Packages"
        return plan.isBlocked ? "Can't Uninstall \(subject) on Its Own" : "Uninstall \(subject)?"
    }

    /// "Uninstall shellcheck and actionlint", or a count when the list is long
    private static func uninstallButtonTitle(_ names: [String]) -> String {
        switch names.count {
        case 1: "Uninstall \(names[0])"
        case 2: "Uninstall \(names[0]) and \(names[1])"
        default: "Uninstall All \(names.count) Packages"
        }
    }

    private func confirmationMessage(for action: ScriptAction) -> String {
        let steps = "The run also backs up your Brewfile and runs brew doctor, the security scan and cleanup, "
            + "just like the scheduled run."
        switch action {
        case .update:
            let count = model.upgradablePackages.count
            return "Updates Homebrew and upgrades all outdated packages (\(count) right now), "
                + "skipping pinned and excluded ones. " + steps
        case .upgrade(let packages):
            return "Updates Homebrew and upgrades \(packages.joined(separator: ", ")). " + steps
        case .dryRun:
            return "Shows what would be upgraded without changing anything."
        }
    }

    /// `@ViewBuilder` lets a function return different view types from a switch
    @ViewBuilder
    private func detail(for section: AppModel.Section) -> some View {
        switch section {
        case .dashboard: DashboardView()
        case .installed: InstalledView()
        case .runs: RunsView()
        case .security: SecurityView()
        case .doctor: DoctorView()
        case .backups: BackupsView()
        }
    }

    private func badgeCount(for section: AppModel.Section) -> Int {
        switch section {
        case .installed: model.outdatedPackages.count
        case .doctor: model.doctorIssues.count { $0.importance != .informational }
        default: 0
        }
    }
}

/// Toolbar controls: Dry Run and Update All side by side, or Stop while the app's run is active.
/// The keyboard shortcuts live in the Run menu (`RunMenuItems`), so they aren't repeated here.
private struct RunControl: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let live = model.liveRun, live.isActive {
            Button {
                model.stopLiveRun()
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .labelStyle(.titleAndIcon)
            .help("Stop the running update (⌘.)")
        } else if model.isRunInProgress {
            // Started elsewhere (the LaunchAgent or Terminal); the app can only watch it
            Label("Update running", systemImage: "arrow.triangle.2.circlepath")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.blue)
        } else {
            // Toolbars show icons only by default; `.titleAndIcon` keeps the words visible
            Button {
                model.request(.dryRun)
            } label: {
                Label(ScriptAction.dryRun.title, systemImage: ScriptAction.dryRun.systemImage)
            }
            .labelStyle(.titleAndIcon)
            .disabled(!model.canStartRun)
            .help("See what would be upgraded, without changing anything (⇧⌘U)")

            Button {
                model.request(.update)
            } label: {
                Label(updateTitle, systemImage: ScriptAction.update.systemImage)
            }
            .labelStyle(.titleAndIcon)
            // The accent-coloured style marks the button that changes things
            .buttonStyle(.borderedProminent)
            .disabled(!model.canStartRun)
            .help("Upgrade all outdated packages, after asking (⌘U)")
        }
    }

    /// "Update All · 2" when there's something to upgrade
    private var updateTitle: String {
        let count = model.upgradablePackages.count
        return count > 0 ? "\(ScriptAction.update.title) · \(count)" : ScriptAction.update.title
    }
}

/// Shown when ~/bin has a script too old to write run summaries.
private struct ScriptOutdatedBanner: View {
    let version: SemanticVersion?

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
            Spacer()
            Text("Run scripts/setup.sh in the repo to deploy")
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.12))
    }

    private var message: String {
        if let version {
            "Deployed script is v\(version); the app needs v\(SystemStatus.minimumScriptVersion) or newer."
        } else {
            "No deployed script found at ~/bin/brew-updates.command."
        }
    }
}

#Preview {
    ContentView()
        .environment(AppModel())
        .frame(width: 1000, height: 640)
}

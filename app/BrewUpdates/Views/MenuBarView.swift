import SwiftUI

/// The icon in the menu bar: a mug, plus the number of outdated packages when there are any.
/// It turns into arrows while a run is going and a warning triangle when the last run failed.
struct MenuBarLabel: View {
    let model: AppModel

    private var icon: String {
        if model.isRunInProgress {
            "arrow.triangle.2.circlepath"
        } else if model.latestRunNeedsAttention {
            "exclamationmark.triangle"
        } else {
            "mug"
        }
    }

    var body: some View {
        // `Group` lets one modifier (.task) apply to whichever branch of the `if` is shown.
        // Each branch picks its own label style; SwiftUI applies styles while laying out the view.
        Group {
            let count = model.outdatedPackages.count
            if count > 0 {
                Label("\(count)", systemImage: icon)
                    .labelStyle(.titleAndIcon)
            } else {
                Label("Brew Updates", systemImage: icon)
                    .labelStyle(.iconOnly)
            }
        }
        // Load data even if the main window was closed at launch
        .task { await model.start() }
        // The Dock icon shows the same count. `initial: true` also runs this on first appearance.
        .onChange(of: model.outdatedPackages.count, initial: true) { _, count in
            NSApp.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
        }
    }
}

/// The menu shown when clicking the menu bar icon. In the default menu style, each Text
/// and Button becomes a menu item.
struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    // `openWindow` is an action SwiftUI provides through the environment
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if let run = model.latestRun {
            Text("Last run: \(run.status.title), \(run.date.relativeDescription)")
        }
        if model.latestRunNeedsAttention, let run = model.latestSummarizedRun {
            Button("Show What Went Wrong…") {
                model.open(.run(run.id))
                showMainWindow()
            }
        }
        if model.isRunInProgress {
            Text("Update running now…")
        }
        Text(updatesText)
        if let next = model.nextScheduledRun {
            Text("Next run: \(next.formatted(date: .abbreviated, time: .shortened))")
        }

        Divider()

        if let live = model.liveRun, live.isActive {
            Button("Show Output…") { showMainWindow(section: .runs) }
            Button("Stop Update") { model.stopLiveRun() }
        } else {
            // Confirmation happens in the main window, so open it first
            Button("Update All…") {
                showMainWindow()
                model.request(.update)
            }
            .disabled(!model.canStartRun)
            Button("Dry Run") {
                showMainWindow()
                model.request(.dryRun)
            }
            .disabled(!model.canStartRun)
        }

        Divider()

        Button("Open Brew Updates…") { showMainWindow() }
            .keyboardShortcut("o")
        Button("Settings…") {
            openSettings()
            // A menu bar app isn't frontmost, so bring the new window forward
            NSApp.activate()
        }
        .keyboardShortcut(",")
        Button("Help") {
            openWindow(id: HelpTopic.windowID)
            NSApp.activate()
        }
        Button("Refresh") {
            Task { await model.refresh() }
        }
        .keyboardShortcut("r")

        Divider()

        // A Text in a menu is shown as a greyed-out, unclickable item
        Text("Version \(AppVersion.current.description)")
        Button("Quit") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func showMainWindow(section: AppModel.Section? = nil) {
        if let section {
            model.selectedSection = section
        }
        openWindow(id: "main")
        NSApp.activate()
    }

    private var updatesText: String {
        switch model.outdatedPackages.count {
        case 0: "All packages up to date"
        case 1: "1 update available"
        case let count: "\(count) updates available"
        }
    }
}

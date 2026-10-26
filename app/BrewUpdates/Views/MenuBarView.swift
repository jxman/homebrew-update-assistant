import SwiftUI

/// The icon in the menu bar: a mug, plus the number of outdated packages when there are any.
struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        let count = model.outdatedPackages.count
        Label(count > 0 ? "\(count)" : "Brew Updates", systemImage: model.isRunInProgress ? "arrow.triangle.2.circlepath" : "mug")
            .labelStyle(count > 0 ? AnyLabelStyle(.titleAndIcon) : AnyLabelStyle(.iconOnly))
            // Load data even if the main window was closed at launch
            .task { await model.start() }
    }
}

/// The menu shown when clicking the menu bar icon. In the default menu style, each Text
/// and Button becomes a menu item.
struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    // `openWindow` is an action SwiftUI provides through the environment
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let run = model.latestRun {
            Text("Last run: \(run.status.title), \(run.date.relativeDescription)")
        }
        if model.isRunInProgress {
            Text("Update running now…")
        }
        Text(updatesText)
        if let next = model.nextScheduledRun {
            Text("Next run: \(next.formatted(date: .abbreviated, time: .shortened))")
        }

        Divider()

        Button("Open Brew Updates…") {
            openWindow(id: "main")
            NSApp.activate()
        }
        .keyboardShortcut("o")
        Button("Refresh") {
            Task { await model.refresh() }
        }
        .keyboardShortcut("r")

        Divider()

        Button("Quit") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private var updatesText: String {
        switch model.outdatedPackages.count {
        case 0: "All packages up to date"
        case 1: "1 update available"
        case let count: "\(count) updates available"
        }
    }
}

/// Type-erased label style so the label can switch styles at runtime.
private struct AnyLabelStyle: LabelStyle {
    private let make: (Configuration) -> AnyView

    init(_ style: some LabelStyle) {
        make = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View {
        make(configuration)
    }
}

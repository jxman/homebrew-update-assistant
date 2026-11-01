import SwiftUI

/// The Run menu in the macOS menu bar: Dry Run (⇧⌘U), Update All… (⌘U), and Stop (⌘.) while
/// the app's own run is going. Commands can't read `@Environment(AppModel.self)`, so the model
/// is passed in; reading its properties in `body` still updates the menu when they change.
struct RunMenuItems: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if model.liveRun?.isActive == true {
            Button("Stop") { model.stopLiveRun() }
                .keyboardShortcut(".")
        } else {
            Button(ScriptAction.dryRun.title) { start(.dryRun) }
                .keyboardShortcut("u", modifiers: [.command, .shift])
                .disabled(!model.canStartRun)
            Button("\(ScriptAction.update.title)…") { start(.update) }
                .keyboardShortcut("u")
                .disabled(!model.canStartRun)
        }
    }

    /// Update All's confirmation dialog and the live output are in the main window, so make
    /// sure it's open (the shortcut also works from the Help or Settings window)
    private func start(_ action: ScriptAction) {
        openWindow(id: "main")
        model.request(action)
    }
}

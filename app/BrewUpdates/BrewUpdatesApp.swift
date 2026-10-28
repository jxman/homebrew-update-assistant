import SwiftUI

/// App entry point. A SwiftUI app is a set of *scenes*: here, one main window, the Settings
/// window and a menu bar item, all sharing the same `AppModel`.
@main
struct BrewUpdatesApp: App {
    /// Connects an AppKit `NSApplicationDelegate` for the few things SwiftUI has no API for,
    /// here confirming Quit while an update is running. SwiftUI creates it once.
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    /// The delegate owns the model so the scenes below and the quit handling share one instance.
    private var model: AppModel { appDelegate.model }

    var body: some Scene {
        // `Window` (not `WindowGroup`) because there is only ever one main window
        Window("Brew Updates", id: "main") {
            ContentView()
                // Puts the model in the environment so any view below can read it
                // with `@Environment(AppModel.self)`
                .environment(model)
                .frame(minWidth: 960, minHeight: 600)
        }
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Refresh") {
                    Task { await model.refresh() }
                }
                .keyboardShortcut("r")
            }
            // `CommandMenu` adds a whole new menu to the menu bar, between View and Window
            CommandMenu("Run") {
                RunMenuItems(model: model)
            }
            // `replacing: .help` swaps out the default Help item, which only works with an
            // Apple Help Book, for one that opens the Help window below
            CommandGroup(replacing: .help) {
                HelpMenuButton()
            }
        }

        // A second single window, opened with `openWindow(id: "help")`
        Window("Brew Updates Help", id: HelpTopic.windowID) {
            HelpView()
                .frame(minWidth: 640, minHeight: 420)
        }
        .defaultSize(width: 820, height: 560)

        // `Settings` adds "Settings…" (⌘,) to the app menu and opens this in its own window
        Settings {
            SettingsView()
                .environment(model)
        }

        MenuBarExtra {
            MenuBarView()
                .environment(model)
        } label: {
            MenuBarLabel(model: model)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    /// Quitting closes the script's output pipe, which would kill it mid-upgrade without a
    /// summary. Ask first, then stop it cleanly and quit once it has exited.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model.liveRun?.isActive == true else { return .terminateNow }

        let alert = NSAlert()
        alert.messageText = "An update is still running"
        alert.informativeText = "Quitting stops it, like pressing Ctrl-C in Terminal. The run is recorded as cancelled."
        alert.addButton(withTitle: "Stop and Quit")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }

        model.stopLiveRun()
        Task {
            await model.waitForLiveRun(timeout: .seconds(15))
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

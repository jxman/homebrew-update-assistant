import AppKit
import SwiftUI

/// The app's `NSApplicationDelegate`, connected in `BrewUpdatesApp` with
/// `@NSApplicationDelegateAdaptor`. It owns the shared `AppModel` and handles the few things
/// SwiftUI has no API for: notification clicks at launch and confirming Quit during a run.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    /// Clicking a notification opens its run through the `brewupdates://` link, the same way
    /// as from Terminal, so SwiftUI brings up the main window even if it was closed.
    func applicationWillFinishLaunching(_ notification: Notification) {
        model.notifications.onOpenRun = { runID in
            if let url = URL(string: "\(AppLink.scheme)://run/\(runID)") {
                NSWorkspace.shared.open(url)
            }
        }
        model.notifications.activate()
    }

    /// SwiftUI's `openWindow` action, handed over by the menu bar label (which exists for the
    /// app's whole life). AppKit code like this delegate has no other way to open a scene.
    var openWindow: OpenWindowAction?

    /// Called when the app is already running and its icon is clicked again (Dock, Finder,
    /// the Desktop alias). When the script started the app in the background, the main window
    /// is `.suppressed`, which SwiftUI also applies to reopening, so open it ourselves.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag, let openWindow else { return true }
        openWindow(id: "main")
        NSApp.activate()
        // false = we handled it, AppKit/SwiftUI shouldn't do their default
        return false
    }

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

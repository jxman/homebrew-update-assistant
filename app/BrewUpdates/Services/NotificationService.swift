import Foundation
import UserNotifications

/// Shows the app's notifications in Notification Center.
///
/// `UNUserNotificationCenter` is Apple's notification API. Notifications posted through it
/// belong to this app: they show the app's icon, are listed under "Brew Updates" in System
/// Settings → Notifications, and clicking one comes back to this object (the center's
/// *delegate*), which hands the run ID to `onOpenRun`.
@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    // `nonisolated`: read by the delegate methods below, which aren't on the main actor
    nonisolated private static let fromAppKey = "fromApp"

    /// Called with the run ID when the user clicks a notification
    var onOpenRun: ((String) -> Void)?

    private var center: UNUserNotificationCenter { .current() }

    /// Becomes the center's delegate. Call once at launch, before a click can arrive: macOS
    /// starts the app to deliver a click on a notification even when it isn't running.
    func activate() {
        center.delegate = self
    }

    /// Asks for permission the first time (macOS shows its "Allow notifications?" prompt);
    /// after that it returns the user's choice without asking again.
    @discardableResult
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func post(_ notification: RunNotification) async {
        guard await requestAuthorization() else { return }
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        // Groups the notifications of all runs together in Notification Center
        content.threadIdentifier = "runs"
        content.userInfo = [Self.fromAppKey: notification.isFromApp]
        // The run ID as the identifier: posting the same run twice replaces the first
        // notification instead of adding another. `trigger: nil` means show it now.
        let request = UNNotificationRequest(identifier: notification.runID, content: content, trigger: nil)
        try? await center.add(request)
    }

    // MARK: UNUserNotificationCenterDelegate
    // The center calls these from its own thread, so they are `nonisolated` (not on the main
    // actor) and only hop to the main actor for `onOpenRun`.

    /// The user clicked a notification.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let runID = response.notification.request.identifier
        await MainActor.run { onOpenRun?(runID) }
    }

    /// Only called while the app is frontmost; by default macOS would then show nothing. Runs
    /// started from the app go straight to the list (the user is watching them); others, such
    /// as the scheduled run, also show a banner.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let isFromApp = notification.request.content.userInfo[Self.fromAppKey] as? Bool ?? false
        return isFromApp ? [.list] : [.banner, .sound, .list]
    }
}

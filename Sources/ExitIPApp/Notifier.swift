import Foundation
import UserNotifications
import ExitIPCore

final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private enum Identifier {
        static let portalCategory = "captive-portal"
        static let openSignIn = "open-sign-in"
    }

    /// Called when the user taps the sign-in button (or the notification itself)
    /// on a captive-portal notification.
    var onOpenSignIn: () -> Void = {}

    /// nil when running without a bundle id (e.g. `swift run`), so the
    /// UNUserNotificationCenter API is never touched and cannot crash.
    private var center: UNUserNotificationCenter? {
        guard Bundle.main.bundleIdentifier != nil else { return nil }
        return UNUserNotificationCenter.current()
    }

    /// Registers the action buttons and takes delivery of taps. Call once at
    /// launch, before any notification can be posted.
    func activate() {
        guard let center else { return }
        center.delegate = self
        let open = UNNotificationAction(identifier: Identifier.openSignIn, title: "Open sign-in page", options: [.foreground])
        let portal = UNNotificationCategory(identifier: Identifier.portalCategory, actions: [open], intentIdentifiers: [])
        center.setNotificationCategories([portal])
    }

    func requestAuthorization() {
        center?.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(_ note: AppNotification) {
        guard let center else {
            NSLog("notify (no bundle): \(note.title) — \(note.body)")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = note.title
        content.body = note.body
        if note.action == .openSignIn { content.categoryIdentifier = Identifier.portalCategory }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request)
    }

    // MARK: UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let isPortal = response.notification.request.content.categoryIdentifier == Identifier.portalCategory
        let tappedBody = response.actionIdentifier == UNNotificationDefaultActionIdentifier
        if response.actionIdentifier == Identifier.openSignIn || (isPortal && tappedBody) {
            DispatchQueue.main.async { self.onOpenSignIn() }
        }
        completionHandler()
    }

    // A menu-bar app has no "foreground" to speak of; always show the banner.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

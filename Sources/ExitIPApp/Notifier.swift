import Foundation
import UserNotifications
import ExitIPCore

final class Notifier {
    /// nil when running without a bundle id (e.g. `swift run`), so the
    /// UNUserNotificationCenter API is never touched and cannot crash.
    private var center: UNUserNotificationCenter? {
        guard Bundle.main.bundleIdentifier != nil else { return nil }
        return UNUserNotificationCenter.current()
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
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request)
    }
}

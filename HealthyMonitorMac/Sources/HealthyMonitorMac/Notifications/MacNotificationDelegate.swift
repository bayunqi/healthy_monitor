import Foundation
import UserNotifications
import AppKit

/// Handles notification action button taps and posts to AppDelegate for processing.
final class MacNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {

    nonisolated(unsafe) static let shared = MacNotificationDelegate()

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let category = response.notification.request.content.categoryIdentifier
        var actionId = response.actionIdentifier

        if actionId == UNNotificationDefaultActionIdentifier {
            // Banner tap: for reminders → mark done; for focus prompt → dismiss
            actionId = category == "FOCUS_PROMPT" ? "DISMISS_PROMPT" : "DONE"
        }

        let info: [String: Any] = [
            "action": actionId,
            "logId": userInfo["logId"] as? String ?? "",
            "reminderType": userInfo["reminderType"] as? String ?? ""
        ]
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .reminderResponseReceived,
                object: nil,
                userInfo: info
            )
        }
        completionHandler()
    }

    // Allow notifications to display while app is active (menu bar)
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

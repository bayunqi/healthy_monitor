import AppKit
import SwiftUI
import HealthyMonitorCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon — menu bar only app
        NSApp.setActivationPolicy(.accessory)

        // Initialize the UNUserNotificationCenterDelegate before requesting auth
        _ = MacNotificationDelegate.shared

        // Register notification categories and request permission
        Task {
            await NotificationService.shared.registerCategories()
            _ = try? await NotificationService.shared.requestAuthorization()
        }

        // Bootstrap the app state (loads profile, starts reminder engine)
        Task { await appState.bootstrap() }

        // Create the menu bar icon
        statusBarController = StatusBarController(appState: appState)

        // Handle notification responses
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNotificationResponse(_:)),
            name: .reminderResponseReceived,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task {
            await appState.endFocusSession()
            await appState.engine?.stop()
        }
    }

    @objc private func handleNotificationResponse(_ notification: Foundation.Notification) {
        guard let info = notification.userInfo,
              let rawAction = info["action"] as? String else { return }

        Task {
            // Focus prompt actions don't carry log metadata
            if rawAction == "START_SESSION" {
                await appState.startFocusSession()
                await appState.refreshStats()
                return
            }
            if rawAction == "DISMISS_PROMPT" { return }

            // Reminder actions require log ID and type
            guard let logIdString = info["logId"] as? String,
                  let logId = UUID(uuidString: logIdString),
                  let rawType = info["reminderType"] as? String,
                  let type = ReminderType(rawValue: rawType) else { return }

            switch rawAction {
            case "DONE":
                try? await appState.logger?.recordResponse(for: logId, response: .completed)
            case "SKIP":
                try? await appState.logger?.recordResponse(for: logId, response: .skipped)
            case "SNOOZE":
                await appState.engine?.snooze(entryId: logId, type: type)
            default:
                break
            }
            await appState.refreshStats()
        }
    }
}

// MARK: - Notification name

extension Notification.Name {
    static let reminderResponseReceived = Notification.Name("reminderResponseReceived")
}

import SwiftUI
import HealthyMonitorCore

@main
struct HealthyMonitorMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No visible window — the app lives in the menu bar.
        // Settings window is opened from the menu bar popover.
        Settings {
            SettingsView()
                .environmentObject(appDelegate.appState)
        }
    }
}

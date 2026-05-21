import AppKit
import SwiftUI
import HealthyMonitorCore

/// Owns the NSStatusItem and manages the popover lifecycle.
@MainActor
final class StatusBarController {
    private var statusItem: NSStatusItem
    private var popover: NSPopover
    private var appState: AppState
    private var eventMonitor: Any?

    init(appState: AppState) {
        self.appState = appState
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()

        // All stored properties initialized — can now use self
        popover.contentSize = NSSize(width: 300, height: 380)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView().environmentObject(appState)
        )

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "heart.fill", accessibilityDescription: "HealthyMonitor")
            button.image?.isTemplate = true
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            closePopover()
        } else {
            openPopover(relativeTo: sender)
        }
    }

    private func openPopover(relativeTo button: NSView) {
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // Dismiss when clicking outside
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopover()
        }
    }

    private func closePopover() {
        popover.performClose(nil)
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    /// Updates the status bar icon tint based on today's compliance.
    func updateIcon(complianceRate: Double) {
        let name: String
        switch complianceRate {
        case 0.7...: name = "heart.fill"
        case 0.4..<0.7: name = "heart.slash"
        default: name = "heart"
        }
        statusItem.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        statusItem.button?.image?.isTemplate = true
    }
}

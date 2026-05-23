import Foundation

/// Abstraction over notification scheduling so non-UI test contexts can inject a no-op.
/// Production code uses `NotificationService.shared`; tests use `NoOpNotificationScheduler`.
public protocol NotificationScheduling: Sendable {
    func schedule(id: String, type: ReminderType, fireDate: Date) async throws
    func scheduleCheckIn(id: String) async throws
}

/// Test-only no-op scheduler. Records calls so tests can assert on them.
public actor NoOpNotificationScheduler: NotificationScheduling {
    public private(set) var scheduledIds: [String] = []
    public private(set) var checkInIds: [String] = []
    public init() {}
    public func schedule(id: String, type: ReminderType, fireDate: Date) async throws {
        scheduledIds.append(id)
    }
    public func scheduleCheckIn(id: String) async throws {
        checkInIds.append(id)
    }
}

#if canImport(UserNotifications)
@preconcurrency import UserNotifications

public enum NotificationActionIdentifier: String {
    case done           = "DONE"
    case skip           = "SKIP"
    case snooze         = "SNOOZE"
    case startSession   = "START_SESSION"
    case dismissPrompt  = "DISMISS_PROMPT"
    case stillFocusing  = "STILL_FOCUSING"
    case endFocus       = "END_FOCUS"
}

public enum NotificationCategoryIdentifier: String {
    case reminder     = "REMINDER"
    case focusPrompt  = "FOCUS_PROMPT"
    case focusCheckIn = "FOCUS_CHECKIN"
}

private let focusPromptNotificationId = "focus-prompt-proactive"
private let focusCheckInNotificationId = "focus-checkin-still-here"

public actor NotificationService: NotificationScheduling {
    public static let shared = NotificationService()
    private init() {}

    // MARK: - Permission

    public func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
    }

    public func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    // MARK: - Category registration — call once at app launch

    public func registerCategories() {
        let done   = UNNotificationAction(identifier: NotificationActionIdentifier.done.rawValue,
                                          title: "Done ✓", options: [.foreground])
        let skip   = UNNotificationAction(identifier: NotificationActionIdentifier.skip.rawValue,
                                          title: "Skip", options: [])
        let snooze = UNNotificationAction(identifier: NotificationActionIdentifier.snooze.rawValue,
                                          title: "Snooze 10 min", options: [])
        let reminderCategory = UNNotificationCategory(
            identifier: NotificationCategoryIdentifier.reminder.rawValue,
            actions: [done, skip, snooze],
            intentIdentifiers: []
        )

        let startSession = UNNotificationAction(
            identifier: NotificationActionIdentifier.startSession.rawValue,
            title: "Start Focus Session",
            options: [.foreground]
        )
        let dismiss = UNNotificationAction(
            identifier: NotificationActionIdentifier.dismissPrompt.rawValue,
            title: "Not Now",
            options: []
        )
        let focusCategory = UNNotificationCategory(
            identifier: NotificationCategoryIdentifier.focusPrompt.rawValue,
            actions: [startSession, dismiss],
            intentIdentifiers: []
        )

        let stillFocusing = UNNotificationAction(
            identifier: NotificationActionIdentifier.stillFocusing.rawValue,
            title: "Yes, keep going",
            options: [.foreground]
        )
        let endFocus = UNNotificationAction(
            identifier: NotificationActionIdentifier.endFocus.rawValue,
            title: "End session",
            options: [.foreground, .destructive]
        )
        let checkInCategory = UNNotificationCategory(
            identifier: NotificationCategoryIdentifier.focusCheckIn.rawValue,
            actions: [stillFocusing, endFocus],
            intentIdentifiers: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([reminderCategory, focusCategory, checkInCategory])
    }

    // MARK: - Reminder scheduling

    public func schedule(id: String, type: ReminderType, fireDate: Date) async throws {
        let content = UNMutableNotificationContent()
        content.title = "\(type.emoji) \(type.displayName)"
        content.body  = body(for: type)
        content.sound = .default
        content.categoryIdentifier = NotificationCategoryIdentifier.reminder.rawValue
        content.userInfo = ["reminderType": type.rawValue, "logId": id]

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try await UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Proactive focus prompt scheduling

    public func scheduleProactivePrompt(at fireDate: Date) async throws {
        // Cancel any previously scheduled prompt first
        cancelFocusPrompt()

        let content = UNMutableNotificationContent()
        content.title = "Ready to focus?"
        content.body  = "It's your usual time to start a focus session. Want to begin?"
        content.sound = .default
        content.categoryIdentifier = NotificationCategoryIdentifier.focusPrompt.rawValue

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: focusPromptNotificationId,
            content: content,
            trigger: trigger
        )
        try await UNUserNotificationCenter.current().add(request)
    }

    public func cancelFocusPrompt() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [focusPromptNotificationId])
    }

    // MARK: - Focus check-in ("Still focusing?") prompt

    /// Fires an immediate "Still focusing?" check-in. Used after 2 consecutive missed reminders
    /// to give the user a one-tap way to stay in or end the session. The `id` parameter lets
    /// callers correlate, but we always overwrite the single pending check-in so it can't pile up.
    public func scheduleCheckIn(id: String = "") async throws {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [focusCheckInNotificationId])
        let content = UNMutableNotificationContent()
        content.title = "Still focusing?"
        content.body  = "We haven't heard from you in a while. Are you still in your focus session?"
        content.sound = .default
        content.categoryIdentifier = NotificationCategoryIdentifier.focusCheckIn.rawValue
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(
            identifier: focusCheckInNotificationId,
            content: content,
            trigger: trigger
        )
        try await UNUserNotificationCenter.current().add(request)
    }

    public func cancelCheckIn() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [focusCheckInNotificationId])
    }

    // MARK: - General cancel

    public func cancel(id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }

    public func cancelAll() async {
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier))
    }

    // MARK: - Private

    private func body(for type: ReminderType) -> String {
        switch type {
        case .stand:   return "You've been sitting a while. Stand up and move for a minute."
        case .water:   return "Stay hydrated — time for a glass of water."
        case .stretch: return "A quick stretch helps your back and neck. 60 seconds is enough."
        }
    }
}

#else

// MARK: - Stub for platforms without UserNotifications (Linux, etc.)

public actor NotificationService: NotificationScheduling {
    public static let shared = NotificationService()
    private init() {}
    public func requestAuthorization() async throws -> Bool { false }
    public func registerCategories() {}
    public func schedule(id: String, type: ReminderType, fireDate: Date) async throws {}
    public func scheduleProactivePrompt(at fireDate: Date) async throws {}
    public func cancelFocusPrompt() {}
    public func scheduleCheckIn(id: String = "") async throws {}
    public func cancelCheckIn() {}
    public func cancel(id: String) {}
    public func cancelAll() async {}
}

#endif

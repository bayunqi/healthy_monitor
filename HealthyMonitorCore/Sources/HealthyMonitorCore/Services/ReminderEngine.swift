import Foundation

/// The heartbeat engine. Manages reminder scheduling and fires notifications.
/// All mutable state is isolated behind actor; safe to call from any context.
public actor ReminderEngine {

    public enum State: Sendable {
        case stopped
        case running
        case paused(until: Date?)
    }

    private var state: State = .stopped
    private var activeFocusSessionId: UUID? = nil
    private var configs: [ReminderType: ReminderConfigData]
    private var profile: HealthProfileData
    private var heartbeatTask: Task<Void, Never>?
    private let logger: ActivityLogger
    private let notifications: any NotificationScheduling

    /// Session-local counter of consecutive missed reminders (since the last positive response
    /// or the last "Still focusing" acknowledgment). Drives the two-stage auto-exit safety net.
    private var consecutiveMissedCount: Int = 0
    /// Set true once the "Still focusing?" prompt has been fired for the current run of misses.
    private var checkInPromptFiredForCurrentRun: Bool = false
    /// Floor timestamp: only entries strictly after this time count toward the miss run.
    /// Set when the user acknowledges "Still focusing" so pre-acknowledgment misses don't carry over.
    private var inactivityFloor: Date? = nil
    /// Callback invoked when the engine has decided the active session should auto-end.
    /// The host (AppState) wires this up to actually persist + clean up.
    public var onAutoEndRequested: (@Sendable (UUID) async -> Void)?

    public static let minIntervalMinutes = 15
    public static let maxIntervalMinutes = 120
    /// After this many consecutive missed reminders, fire the "Still focusing?" check-in.
    public static let checkInMissThreshold = 2
    /// After this many consecutive missed reminders, auto-end the session.
    public static let autoEndMissThreshold = 3

    public init(
        configs: [ReminderConfigData],
        profile: HealthProfileData,
        logger: ActivityLogger,
        notifications: any NotificationScheduling
    ) {
        var map: [ReminderType: ReminderConfigData] = [:]
        for c in configs { map[c.type] = c }
        self.configs = map
        self.profile = profile
        self.logger = logger
        self.notifications = notifications
    }

    // MARK: - Lifecycle

    public func start() {
        guard case .stopped = state else { return }
        state = .running
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    public func stop() {
        state = .stopped
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    public func pause(until date: Date? = nil) {
        state = .paused(until: date)
    }

    public func resume() {
        if case .paused = state { state = .running }
    }

    public var currentState: State { state }

    // MARK: - Focus session control

    public func startFocusSession(id: UUID) {
        activeFocusSessionId = id
        // Anchor the interval clock to session start so the first reminder fires
        // a full intervalMinutes later — not on the next heartbeat tick.
        let sessionStart = Date.now
        for type in ReminderType.allCases { configs[type]?.lastFiredAt = sessionStart }
        consecutiveMissedCount = 0
        checkInPromptFiredForCurrentRun = false
        inactivityFloor = nil
        if case .stopped = state { state = .running }
    }

    public func endFocusSession() {
        activeFocusSessionId = nil
        consecutiveMissedCount = 0
        checkInPromptFiredForCurrentRun = false
        inactivityFloor = nil
        state = .stopped
    }

    /// Called by the host when the user responds "Yes, still focusing" to the check-in prompt.
    /// Resets the counter and sets a floor so existing missed entries no longer count.
    public func acknowledgeStillFocusing() {
        consecutiveMissedCount = 0
        checkInPromptFiredForCurrentRun = false
        inactivityFloor = .now
    }

    public func setOnAutoEndRequested(_ handler: @Sendable @escaping (UUID) async -> Void) {
        self.onAutoEndRequested = handler
    }

    // MARK: - Config updates (called by LLM tool response handler)

    public func updateInterval(for type: ReminderType, minutes: Int) {
        let clamped = min(max(minutes, Self.minIntervalMinutes), Self.maxIntervalMinutes)
        configs[type]?.intervalMinutes = clamped
    }

    public func setEnabled(for type: ReminderType, enabled: Bool) {
        configs[type]?.isEnabled = enabled
    }

    public func isEnabled(for type: ReminderType) -> Bool {
        configs[type]?.isEnabled ?? true
    }

    public func updateProfile(_ newProfile: HealthProfileData) {
        profile = newProfile
    }

    // MARK: - Heartbeat

    /// Test-only hook: runs one heartbeat tick synchronously without the 60s sleep.
    /// Marked internal so only `@testable import` can reach it.
    internal func tickForTest() async { await tick() }

    /// Test-only inspection of session-anchored interval state.
    internal func lastFiredAtForTest(_ type: ReminderType) -> Date? { configs[type]?.lastFiredAt }

    /// Test-only mutation: simulate the passage of time by rewinding lastFiredAt.
    internal func setLastFiredAtForTest(_ type: ReminderType, to date: Date) {
        configs[type]?.lastFiredAt = date
    }

    /// Test-only inspection of the inactivity counter.
    internal func consecutiveMissedCountForTest() -> Int { consecutiveMissedCount }

    /// Test-only inspection of whether the check-in prompt has been fired in the current miss run.
    internal func checkInPromptFiredForTest() -> Bool { checkInPromptFiredForCurrentRun }

    private func tick() async {
        guard let sessionId = activeFocusSessionId else { return }

        switch state {
        case .stopped: return
        case .paused(let until):
            if let until, Date.now >= until { state = .running } else { return }
        case .running: break
        }

        await markStale()
        await evaluateInactivity(sessionId: sessionId)

        // Guard again — evaluateInactivity may have auto-ended the session.
        guard activeFocusSessionId != nil else { return }

        for type in ReminderType.allCases {
            guard let config = configs[type], config.isEnabled else { continue }
            await fireIfDue(type: type, config: config)
        }
    }

    /// Walks the session's resolved entries (most recent first) and counts the trailing
    /// run of `.missed` since the last positive response. Triggers the check-in prompt
    /// and auto-end based on the threshold constants.
    private func evaluateInactivity(sessionId: UUID) async {
        let logs = (try? await logger.logs(for: sessionId)) ?? []
        let resolved = logs
            .filter { entry in
                guard let floor = inactivityFloor,
                      let resolvedAt = entry.respondedAt else { return entry.respondedAt != nil }
                return resolvedAt > floor
            }
            .filter { $0.response != nil }
            .sorted { ($0.respondedAt ?? $0.scheduledAt) > ($1.respondedAt ?? $1.scheduledAt) }
        var run = 0
        for entry in resolved {
            if entry.response == .missed { run += 1 } else { break }
        }
        consecutiveMissedCount = run

        if run >= Self.autoEndMissThreshold {
            // Hand off to the host, then clear engine state so the heartbeat winds down.
            let handler = onAutoEndRequested
            let endingId = sessionId
            activeFocusSessionId = nil
            state = .stopped
            consecutiveMissedCount = 0
            checkInPromptFiredForCurrentRun = false
            if let handler { await handler(endingId) }
        } else if run >= Self.checkInMissThreshold, !checkInPromptFiredForCurrentRun {
            try? await notifications.scheduleCheckIn(id: sessionId.uuidString)
            checkInPromptFiredForCurrentRun = true
        } else if run == 0 {
            checkInPromptFiredForCurrentRun = false
        }
    }

    private func markStale() async {
        try? await logger.markStaleMissed(gracePeriodMinutes: 5)
    }

    private func fireIfDue(type: ReminderType, config: ReminderConfigData) async {
        let now = Date.now

        // Quiet hours — always respected even during a focus session
        if let startH = profile.quietHoursStartHour,
           let endH = profile.quietHoursEndHour,
           now.isInQuietHours(startHour: startH, endHour: endH) { return }

        // Interval check
        if let lastFired = config.lastFiredAt {
            let elapsed = now.timeIntervalSince(lastFired) / 60
            guard elapsed >= Double(config.intervalMinutes) else { return }
        }

        await fire(type: type, at: now)
        configs[type]?.lastFiredAt = now
        configs[type]?.nextScheduledAt = config.scheduledFireDate(from: now)
    }

    private func fire(type: ReminderType, at date: Date) async {
        do {
            let entry = try await logger.createEntry(
                type: type,
                scheduledAt: date,
                focusSessionId: activeFocusSessionId
            )
            try await notifications.schedule(id: entry.id.uuidString, type: type, fireDate: date)
        } catch {
            print("[ReminderEngine] Failed to fire \(type.rawValue): \(error)")
        }
    }

    // MARK: - Snooze

    public func snooze(entryId: UUID, type: ReminderType, durationMinutes: Int = 10) async {
        let snoozeDate = Date.now.addingTimeInterval(TimeInterval(durationMinutes * 60))
        do {
            try await logger.recordResponse(for: entryId, response: .snoozed)
            let newEntry = try await logger.createEntry(
                type: type,
                scheduledAt: snoozeDate,
                focusSessionId: activeFocusSessionId
            )
            try await notifications.schedule(id: newEntry.id.uuidString, type: type, fireDate: snoozeDate)
        } catch {
            print("[ReminderEngine] Snooze failed: \(error)")
        }
    }
}

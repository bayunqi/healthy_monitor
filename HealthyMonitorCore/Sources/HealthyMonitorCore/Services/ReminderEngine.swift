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
    private let notifications: NotificationService

    public static let minIntervalMinutes = 15
    public static let maxIntervalMinutes = 120

    public init(
        configs: [ReminderConfigData],
        profile: HealthProfileData,
        logger: ActivityLogger,
        notifications: NotificationService
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
        // Reset interval countdowns so first reminder fires after a full interval from session start
        for type in ReminderType.allCases { configs[type]?.lastFiredAt = nil }
        if case .stopped = state { state = .running }
    }

    public func endFocusSession() {
        activeFocusSessionId = nil
        state = .stopped
    }

    // MARK: - Config updates (called by LLM tool response handler)

    public func updateInterval(for type: ReminderType, minutes: Int) {
        let clamped = min(max(minutes, Self.minIntervalMinutes), Self.maxIntervalMinutes)
        configs[type]?.intervalMinutes = clamped
    }

    public func updateProfile(_ newProfile: HealthProfileData) {
        profile = newProfile
    }

    // MARK: - Heartbeat

    private func tick() async {
        guard activeFocusSessionId != nil else { return }

        switch state {
        case .stopped: return
        case .paused(let until):
            if let until, Date.now >= until { state = .running } else { return }
        case .running: break
        }

        await markStale()

        for type in ReminderType.allCases {
            guard let config = configs[type], config.isEnabled else { continue }
            await fireIfDue(type: type, config: config)
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
            let entry = try await logger.createEntry(type: type, scheduledAt: date)
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
            let newEntry = try await logger.createEntry(type: type, scheduledAt: snoozeDate)
            try await notifications.schedule(id: newEntry.id.uuidString, type: type, fireDate: snoozeDate)
        } catch {
            print("[ReminderEngine] Snooze failed: \(error)")
        }
    }
}

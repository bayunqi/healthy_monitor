import Foundation

/// Plain Codable config. Stored locally per device; not CloudKit-synced.
public struct ReminderConfigData: Codable, Sendable {
    public var type: ReminderType
    public var intervalMinutes: Int
    public var isEnabled: Bool
    public var lastFiredAt: Date?
    public var nextScheduledAt: Date?
    public var snoozeCount: Int
    public var snoozeDurationMinutes: Int

    public init(type: ReminderType) {
        self.type = type
        self.intervalMinutes = type.defaultIntervalMinutes
        self.isEnabled = true
        self.snoozeCount = 0
        self.snoozeDurationMinutes = 10
    }

    public func scheduledFireDate(from base: Date = .now) -> Date {
        base.addingTimeInterval(TimeInterval(intervalMinutes * 60))
    }
}

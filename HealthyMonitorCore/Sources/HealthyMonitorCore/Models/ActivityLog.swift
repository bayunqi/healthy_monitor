import Foundation

/// Plain Codable activity record. CloudKit-synced by the app target's @Model class.
public struct ActivityLogEntry: Codable, Sendable, Identifiable {
    public let id: UUID
    public var type: ReminderType
    public var scheduledAt: Date
    public var respondedAt: Date?
    public var response: ActivityResponse?
    public var deviceSource: String

    public var isResolved: Bool { response != nil }

    public init(type: ReminderType, scheduledAt: Date, deviceSource: String = "mac") {
        self.id = UUID()
        self.type = type
        self.scheduledAt = scheduledAt
        self.deviceSource = deviceSource
    }
}

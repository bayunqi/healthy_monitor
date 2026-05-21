import Foundation

public struct FocusSession: Codable, Sendable, Identifiable {
    public var id: UUID
    public var startedAt: Date
    public var endedAt: Date?

    public var isActive: Bool { endedAt == nil }

    public var duration: TimeInterval? {
        guard let end = endedAt else { return nil }
        return end.timeIntervalSince(startedAt)
    }

    public init(id: UUID = UUID(), startedAt: Date = .now, endedAt: Date? = nil) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
}

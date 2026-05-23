import Foundation

/// Compliance aggregate scoped to a single focus session. Persisted on `FocusSession`
/// when the session ends so historical sessions carry their own self-contained snapshot.
public struct SessionStats: Codable, Sendable {
    public let byType: [ReminderType: DailyStats.TypeStats]

    public init(byType: [ReminderType: DailyStats.TypeStats]) {
        self.byType = byType
    }

    public var totalReminders: Int { byType.values.reduce(0) { $0 + $1.total } }
    public var totalCompleted: Int { byType.values.reduce(0) { $0 + $1.completed } }

    public var overallComplianceRate: Double {
        guard totalReminders > 0 else { return 0 }
        return Double(totalCompleted) / Double(totalReminders)
    }

    public func stats(for type: ReminderType) -> DailyStats.TypeStats {
        byType[type] ?? .zero
    }

    public static let empty = SessionStats(byType: [:])
}

/// Why a focus session ended. Surfaced in the menu bar so users can tell the difference
/// between an intentional end and the app's auto-end-on-inactivity safety net.
public enum FocusSessionEndReason: String, Codable, Sendable {
    case endedByUser
    case autoEndedDueToInactivity
}

public struct FocusSession: Codable, Sendable, Identifiable {
    public var id: UUID
    public var startedAt: Date
    public var endedAt: Date?
    /// Compliance snapshot, set when the session ends. nil while active.
    public var stats: SessionStats?
    /// Why the session ended. nil while active or for legacy records.
    public var endReason: FocusSessionEndReason?

    public var isActive: Bool { endedAt == nil }

    public var duration: TimeInterval? {
        guard let end = endedAt else { return nil }
        return end.timeIntervalSince(startedAt)
    }

    public init(
        id: UUID = UUID(),
        startedAt: Date = .now,
        endedAt: Date? = nil,
        stats: SessionStats? = nil,
        endReason: FocusSessionEndReason? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.stats = stats
        self.endReason = endReason
    }
}

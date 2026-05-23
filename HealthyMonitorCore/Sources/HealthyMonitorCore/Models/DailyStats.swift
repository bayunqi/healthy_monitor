import Foundation

public struct DailyStats: Sendable {
    public let date: Date
    public let byType: [ReminderType: TypeStats]

    public struct TypeStats: Codable, Sendable {
        public let total: Int
        public let completed: Int
        public let skipped: Int
        public let snoozed: Int
        public let missed: Int

        public var complianceRate: Double {
            guard total > 0 else { return 0 }
            return Double(completed) / Double(total)
        }

        public static let zero = TypeStats(total: 0, completed: 0, skipped: 0, snoozed: 0, missed: 0)
    }

    public var totalReminders: Int { byType.values.reduce(0) { $0 + $1.total } }
    public var totalCompleted: Int { byType.values.reduce(0) { $0 + $1.completed } }

    public var overallComplianceRate: Double {
        guard totalReminders > 0 else { return 0 }
        return Double(totalCompleted) / Double(totalReminders)
    }

    public func stats(for type: ReminderType) -> TypeStats {
        byType[type] ?? .zero
    }

    public static let empty = DailyStats(date: .now, byType: [:])
}

public struct WeeklyStats: Sendable {
    public let days: [DailyStats]

    public var averageComplianceRate: Double {
        let rates = days.map(\.overallComplianceRate)
        guard !rates.isEmpty else { return 0 }
        return rates.reduce(0, +) / Double(rates.count)
    }

    public var standComplianceRate: Double {
        let rates = days.map { $0.stats(for: .stand).complianceRate }
        guard !rates.isEmpty else { return 0 }
        return rates.reduce(0, +) / Double(rates.count)
    }
}

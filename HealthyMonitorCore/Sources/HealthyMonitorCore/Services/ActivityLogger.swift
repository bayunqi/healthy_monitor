import Foundation

// MARK: - Repository protocol


/// Implemented by the app target using SwiftData; implemented by InMemoryActivityLogRepository in tests.
public protocol ActivityLogRepository: Sendable {
    func createEntry(type: ReminderType, scheduledAt: Date, deviceSource: String, focusSessionId: UUID?) async throws -> ActivityLogEntry
    func recordResponse(for id: UUID, response: ActivityResponse) async throws
    func markStaleMissed(gracePeriodMinutes: Int) async throws
    func logs(from: Date, to: Date) async throws -> [ActivityLogEntry]
    func logs(for sessionId: UUID) async throws -> [ActivityLogEntry]
    func recentLogs(limit: Int) async throws -> [ActivityLogEntry]
}

// MARK: - In-memory implementation (used in tests and preview)

public actor InMemoryActivityLogRepository: ActivityLogRepository {
    private var entries: [UUID: ActivityLogEntry] = [:]

    public init() {}

    public func createEntry(type: ReminderType, scheduledAt: Date, deviceSource: String = "mac", focusSessionId: UUID? = nil) async throws -> ActivityLogEntry {
        let entry = ActivityLogEntry(type: type, scheduledAt: scheduledAt, deviceSource: deviceSource, focusSessionId: focusSessionId)
        entries[entry.id] = entry
        return entry
    }

    public func recordResponse(for id: UUID, response: ActivityResponse) async throws {
        guard entries[id] != nil else { return }
        entries[id]?.response = response
        entries[id]?.respondedAt = .now
    }

    public func markStaleMissed(gracePeriodMinutes: Int = 5) async throws {
        let cutoff = Date.now.addingTimeInterval(-TimeInterval(gracePeriodMinutes * 60))
        for id in entries.keys where entries[id]?.response == nil {
            if let scheduledAt = entries[id]?.scheduledAt, scheduledAt < cutoff {
                entries[id]?.response = .missed
                entries[id]?.respondedAt = .now
            }
        }
    }

    public func logs(from: Date, to: Date) async throws -> [ActivityLogEntry] {
        entries.values
            .filter { $0.scheduledAt >= from && $0.scheduledAt <= to }
            .sorted { $0.scheduledAt < $1.scheduledAt }
    }

    public func logs(for sessionId: UUID) async throws -> [ActivityLogEntry] {
        entries.values
            .filter { $0.focusSessionId == sessionId }
            .sorted { $0.scheduledAt < $1.scheduledAt }
    }

    public func recentLogs(limit: Int = 50) async throws -> [ActivityLogEntry] {
        Array(entries.values.sorted { $0.scheduledAt > $1.scheduledAt }.prefix(limit))
    }

    // Test helpers
    public func allEntries() -> [ActivityLogEntry] {
        Array(entries.values)
    }

    public func entry(for id: UUID) -> ActivityLogEntry? {
        entries[id]
    }
}

// MARK: - ActivityLogger (business logic layer)

/// Computes stats and coordinates log writes. Depends only on the repository protocol.
public actor ActivityLogger {
    private let repository: any ActivityLogRepository

    public init(repository: any ActivityLogRepository) {
        self.repository = repository
    }

    @discardableResult
    public func createEntry(type: ReminderType, scheduledAt: Date, deviceSource: String = "mac", focusSessionId: UUID? = nil) async throws -> ActivityLogEntry {
        try await repository.createEntry(type: type, scheduledAt: scheduledAt, deviceSource: deviceSource, focusSessionId: focusSessionId)
    }

    public func recordResponse(for id: UUID, response: ActivityResponse) async throws {
        try await repository.recordResponse(for: id, response: response)
    }

    public func markStaleMissed(gracePeriodMinutes: Int = 5) async throws {
        try await repository.markStaleMissed(gracePeriodMinutes: gracePeriodMinutes)
    }

    public func dailyStats(for date: Date) async throws -> DailyStats {
        let logs = try await repository.logs(from: date.startOfDay, to: date.endOfDay)
        return computeStats(from: logs, date: date)
    }

    /// Compliance stats for a single focus session — aggregates only entries tagged with `sessionId`.
    public func sessionStats(for sessionId: UUID) async throws -> SessionStats {
        let logs = try await repository.logs(for: sessionId)
        return computeSessionStats(from: logs)
    }

    public func logs(for sessionId: UUID) async throws -> [ActivityLogEntry] {
        try await repository.logs(for: sessionId)
    }

    public func weeklyStats(endingOn date: Date = .now) async throws -> WeeklyStats {
        let calendar = Calendar.current
        let days = (0..<7).compactMap {
            calendar.date(byAdding: .day, value: -$0, to: date.startOfDay)
        }.reversed()
        let stats = try await withThrowingTaskGroup(of: DailyStats.self) { group in
            for day in days {
                group.addTask { try await self.dailyStats(for: day) }
            }
            var result: [DailyStats] = []
            for try await s in group { result.append(s) }
            return result.sorted { $0.date < $1.date }
        }
        return WeeklyStats(days: stats)
    }

    public func recentLogs(limit: Int = 50) async throws -> [ActivityLogEntry] {
        try await repository.recentLogs(limit: limit)
    }

    // MARK: - Private

    private func computeStats(from logs: [ActivityLogEntry], date: Date) -> DailyStats {
        DailyStats(date: date, byType: groupByType(logs))
    }

    private func computeSessionStats(from logs: [ActivityLogEntry]) -> SessionStats {
        SessionStats(byType: groupByType(logs))
    }

    private func groupByType(_ logs: [ActivityLogEntry]) -> [ReminderType: DailyStats.TypeStats] {
        var byType: [ReminderType: DailyStats.TypeStats] = [:]
        let grouped = Dictionary(grouping: logs, by: \.type)
        for (type, typeLogs) in grouped {
            byType[type] = DailyStats.TypeStats(
                total: typeLogs.count,
                completed: typeLogs.filter { $0.response == .completed }.count,
                skipped:   typeLogs.filter { $0.response == .skipped }.count,
                snoozed:   typeLogs.filter { $0.response == .snoozed }.count,
                missed:    typeLogs.filter { $0.response == .missed }.count
            )
        }
        return byType
    }
}

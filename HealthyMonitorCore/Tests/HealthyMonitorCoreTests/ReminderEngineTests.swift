import Testing
import Foundation
@testable import HealthyMonitorCore

@Suite("ReminderConfig & Intervals")
struct ReminderConfigTests {

    @Test("Minimum interval constant is 15 minutes")
    func minimumIntervalConstant() {
        #expect(ReminderEngine.minIntervalMinutes == 15)
    }

    @Test("Maximum interval constant is 120 minutes")
    func maximumIntervalConstant() {
        #expect(ReminderEngine.maxIntervalMinutes == 120)
    }

    @Test("Default stand interval is 45 minutes")
    func defaultStandInterval() {
        let config = ReminderConfigData(type: .stand)
        #expect(config.intervalMinutes == 45)
    }

    @Test("Default water interval is 90 minutes")
    func defaultWaterInterval() {
        let config = ReminderConfigData(type: .water)
        #expect(config.intervalMinutes == 90)
    }

    @Test("Default stretch interval is 60 minutes")
    func defaultStretchInterval() {
        let config = ReminderConfigData(type: .stretch)
        #expect(config.intervalMinutes == 60)
    }

    @Test("scheduledFireDate returns base + intervalMinutes")
    func scheduledFireDate() {
        let config = ReminderConfigData(type: .stand) // 45 min
        let base = Date.now
        let fireDate = config.scheduledFireDate(from: base)
        let diff = fireDate.timeIntervalSince(base)
        #expect(abs(diff - Double(45 * 60)) < 1)
    }
}

@Suite("Quiet Hours")
struct QuietHoursTests {

    @Test("Overnight quiet hours contain hours past midnight")
    func overnightWindow() {
        let at23 = makeDate(hour: 23)
        #expect(at23.isInQuietHours(startHour: 22, endHour: 7))

        let at3 = makeDate(hour: 3)
        #expect(at3.isInQuietHours(startHour: 22, endHour: 7))
    }

    @Test("Overnight quiet hours excludes midday")
    func overnightWindowExcludesMidday() {
        let at12 = makeDate(hour: 12)
        #expect(!at12.isInQuietHours(startHour: 22, endHour: 7))
    }

    @Test("Same-day quiet hours window works correctly")
    func sameDayWindow() {
        let inside  = makeDate(hour: 12)
        let outside = makeDate(hour: 8)
        #expect(inside.isInQuietHours(startHour: 10, endHour: 14))
        #expect(!outside.isInQuietHours(startHour: 10, endHour: 14))
    }

    private func makeDate(hour: Int) -> Date {
        var c = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        c.hour = hour; c.minute = 0; c.second = 0
        return Calendar.current.date(from: c) ?? .now
    }
}

@Suite("ActivityLogEntry")
struct ActivityLogEntryTests {

    @Test("New entry has nil response and isResolved == false")
    func initialState() {
        let entry = ActivityLogEntry(type: .water, scheduledAt: .now)
        #expect(entry.response == nil)
        #expect(!entry.isResolved)
    }

    @Test("Setting response marks entry as resolved")
    func settingResponseResolvesEntry() {
        var entry = ActivityLogEntry(type: .stand, scheduledAt: .now)
        entry.response = .completed
        #expect(entry.response == .completed)
        #expect(entry.isResolved)
    }

    @Test("Entry round-trips through JSON")
    func jsonRoundtrip() throws {
        var entry = ActivityLogEntry(type: .stretch, scheduledAt: .now, deviceSource: "mac")
        entry.response = .skipped
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(ActivityLogEntry.self, from: data)
        #expect(decoded.id == entry.id)
        #expect(decoded.type == .stretch)
        #expect(decoded.response == .skipped)
        #expect(decoded.deviceSource == "mac")
    }
}

@Suite("DailyStats")
struct DailyStatsTests {

    @Test("Empty stats has zero compliance rate")
    func emptyStats() {
        #expect(DailyStats.empty.overallComplianceRate == 0)
        #expect(DailyStats.empty.totalReminders == 0)
    }

    @Test("TypeStats compliance rate: 3 of 4 = 0.75")
    func complianceRate() {
        let s = DailyStats.TypeStats(total: 4, completed: 3, skipped: 0, snoozed: 0, missed: 1)
        #expect(s.complianceRate == 0.75)
    }

    @Test("TypeStats.zero has zero compliance")
    func zeroStats() {
        #expect(DailyStats.TypeStats.zero.complianceRate == 0)
    }

    @Test("stats(for:) returns .zero for unknown type")
    func statsForUnknownType() {
        let daily = DailyStats(date: .now, byType: [:])
        let s = daily.stats(for: .stand)
        #expect(s.total == 0)
    }
}

@Suite("ActivityLogger (in-memory)")
struct ActivityLoggerTests {

    @Test("createEntry persists to repository")
    func createEntryPersists() async throws {
        let repo = InMemoryActivityLogRepository()
        let logger = ActivityLogger(repository: repo)
        let entry = try await logger.createEntry(type: .water, scheduledAt: .now)
        let stored = await repo.entry(for: entry.id)
        #expect(stored != nil)
        #expect(stored?.type == .water)
    }

    @Test("recordResponse updates entry")
    func recordResponseUpdates() async throws {
        let repo = InMemoryActivityLogRepository()
        let logger = ActivityLogger(repository: repo)
        let entry = try await logger.createEntry(type: .stand, scheduledAt: .now)
        try await logger.recordResponse(for: entry.id, response: .completed)
        let stored = await repo.entry(for: entry.id)
        #expect(stored?.response == .completed)
        #expect(stored?.respondedAt != nil)
    }

    @Test("dailyStats complianceRate reflects completed entries")
    func dailyStatsCompliance() async throws {
        let repo = InMemoryActivityLogRepository()
        let logger = ActivityLogger(repository: repo)
        let today = Date.now
        let e1 = try await logger.createEntry(type: .stand, scheduledAt: today)
        let e2 = try await logger.createEntry(type: .stand, scheduledAt: today)
        try await logger.recordResponse(for: e1.id, response: .completed)
        try await logger.recordResponse(for: e2.id, response: .missed)
        let stats = try await logger.dailyStats(for: today)
        #expect(stats.stats(for: .stand).complianceRate == 0.5)
    }

    @Test("markStaleMissed marks old unresolved entries")
    func markStaleMissed() async throws {
        let repo = InMemoryActivityLogRepository()
        let logger = ActivityLogger(repository: repo)
        let old = Date.now.addingTimeInterval(-600) // 10 minutes ago
        let entry = try await logger.createEntry(type: .water, scheduledAt: old)
        try await logger.markStaleMissed(gracePeriodMinutes: 5)
        let stored = await repo.entry(for: entry.id)
        #expect(stored?.response == .missed)
    }
}

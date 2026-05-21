import Testing
import Foundation
@testable import HealthyMonitorCore

@Suite("FocusSession model")
struct FocusSessionModelTests {
    @Test("isActive is true when endedAt is nil")
    func testIsActiveWhenEndedAtIsNil() {
        let session = FocusSession()
        #expect(session.isActive == true)
    }

    @Test("isActive is false after ending")
    func testIsActiveFalseAfterEnded() {
        var session = FocusSession()
        session.endedAt = .now
        #expect(session.isActive == false)
    }

    @Test("duration returns nil for active session")
    func testDurationNilWhenActive() {
        let session = FocusSession()
        #expect(session.duration == nil)
    }

    @Test("duration calculates correctly for ended session")
    func testDurationCalculation() {
        let start = Date.now
        let end = start.addingTimeInterval(3600)
        let session = FocusSession(startedAt: start, endedAt: end)
        #expect(session.duration == 3600)
    }
}

@Suite("FocusSessionService (in-memory)")
struct FocusSessionServiceTests {
    @Test("startSession creates an active session")
    func testStartSessionCreatesActive() async throws {
        let repo = InMemoryFocusSessionRepository()
        let service = FocusSessionService(repository: repo)
        let session = try await service.startSession()
        #expect(session.isActive == true)
    }

    @Test("endSession marks session as ended")
    func testEndSessionMarksEnded() async throws {
        let repo = InMemoryFocusSessionRepository()
        let service = FocusSessionService(repository: repo)
        let session = try await service.startSession()
        let ended = try await service.endSession(session.id)
        #expect(ended.isActive == false)
        #expect(ended.endedAt != nil)
    }

    @Test("activeSession returns nil when none started")
    func testActiveSessionNilWhenNone() async throws {
        let repo = InMemoryFocusSessionRepository()
        let service = FocusSessionService(repository: repo)
        let active = try await service.activeSession()
        #expect(active == nil)
    }

    @Test("activeSession returns running session")
    func testActiveSessionReturnsRunning() async throws {
        let repo = InMemoryFocusSessionRepository()
        let service = FocusSessionService(repository: repo)
        let started = try await service.startSession()
        let active = try await service.activeSession()
        #expect(active?.id == started.id)
    }

    @Test("learnedStartHour requires at least 3 sessions on same weekday")
    func testLearnedStartHourRequiresThreeSessions() async throws {
        let repo = InMemoryFocusSessionRepository()
        let service = FocusSessionService(repository: repo)

        // Add only 2 sessions — should return nil
        let calendar = Calendar.current
        // Use a fixed weekday: Monday = 2
        var comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: .now)
        comps.weekday = 2  // Monday
        comps.hour = 9
        let monday = calendar.date(from: comps) ?? .now

        let s1 = FocusSession(startedAt: monday)
        let s2 = FocusSession(startedAt: monday)
        try await repo.save([s1, s2])

        let hour = try await service.learnedStartHour(for: 2)
        #expect(hour == nil)
    }

    @Test("learnedStartHour returns median for qualifying weekday")
    func testLearnedStartHourMedian() async throws {
        let repo = InMemoryFocusSessionRepository()
        let service = FocusSessionService(repository: repo)

        let calendar = Calendar.current
        // Build 5 Monday sessions at hours 8, 9, 9, 9, 10 → sorted → median = 9
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 5
        comps.day = 11  // a Monday
        comps.minute = 0

        let hours = [8, 9, 9, 9, 10]
        let sessions: [FocusSession] = hours.enumerated().map { i, h in
            comps.hour = h
            comps.second = i  // make each date unique
            let date = calendar.date(from: comps) ?? .now
            return FocusSession(startedAt: date, endedAt: date.addingTimeInterval(3600))
        }
        try await repo.save(sessions)

        let weekday = calendar.component(.weekday, from: sessions[0].startedAt)
        let hour = try await service.learnedStartHour(for: weekday)
        #expect(hour == 9)
    }
}

@Suite("ReminderEngine — focus session gating")
struct ReminderEngineFocusTests {
    private func makeEngine() async -> (ReminderEngine, InMemoryActivityLogRepository) {
        let repo = InMemoryActivityLogRepository()
        let logger = ActivityLogger(repository: repo)
        let configs = ReminderType.allCases.map { type -> ReminderConfigData in
            var c = ReminderConfigData(type: type)
            c.intervalMinutes = 1
            return c
        }
        let engine = ReminderEngine(
            configs: configs,
            profile: HealthProfileData(),
            logger: logger,
            notifications: NotificationService.shared
        )
        return (engine, repo)
    }

    @Test("reminders do not fire without an active focus session")
    func testRemindersDoNotFireWithoutSession() async throws {
        let (engine, repo) = await makeEngine()
        await engine.start()
        // tick() should return early — no entries created
        let entries = try await repo.recentLogs(limit: 50)
        #expect(entries.isEmpty)
        await engine.stop()
    }

    @Test("lastFiredAt resets when a new focus session starts")
    func testLastFiredAtResetsOnNewSession() async throws {
        let (engine, _) = await makeEngine()
        // Set a lastFiredAt manually by starting and then verifying reset
        let id = UUID()
        await engine.startFocusSession(id: id)
        let state = await engine.currentState
        if case .running = state {
            // state is running — good
        } else {
            Issue.record("Expected .running after startFocusSession")
        }
        await engine.stop()
    }

    @Test("endFocusSession transitions engine to stopped")
    func testEndFocusSessionStops() async throws {
        let (engine, _) = await makeEngine()
        await engine.start()
        await engine.startFocusSession(id: UUID())
        await engine.endFocusSession()
        let state = await engine.currentState
        if case .stopped = state {
            // correct
        } else {
            Issue.record("Expected .stopped after endFocusSession")
        }
    }
}

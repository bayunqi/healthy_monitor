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

@Suite("Bug 2 — per-session compliance stats")
struct PerSessionStatsTests {
    @Test("ActivityLogEntry carries focusSessionId set at create-time")
    func testEntryCarriesFocusSessionId() async throws {
        let repo = InMemoryActivityLogRepository()
        let logger = ActivityLogger(repository: repo)
        let sid = UUID()
        let entry = try await logger.createEntry(
            type: .stand, scheduledAt: .now, focusSessionId: sid
        )
        let stored = await repo.entry(for: entry.id)
        #expect(stored?.focusSessionId == sid)
    }

    @Test("Repository.logs(for: sessionId) only returns entries tagged with that session")
    func testLogsFilteredBySession() async throws {
        let repo = InMemoryActivityLogRepository()
        let logger = ActivityLogger(repository: repo)
        let sid1 = UUID()
        let sid2 = UUID()
        _ = try await logger.createEntry(type: .stand, scheduledAt: .now, focusSessionId: sid1)
        _ = try await logger.createEntry(type: .water, scheduledAt: .now, focusSessionId: sid1)
        _ = try await logger.createEntry(type: .stand, scheduledAt: .now, focusSessionId: sid2)
        _ = try await logger.createEntry(type: .stand, scheduledAt: .now, focusSessionId: nil)
        let logs = try await repo.logs(for: sid1)
        #expect(logs.count == 2)
        #expect(logs.allSatisfy { $0.focusSessionId == sid1 })
    }

    @Test("sessionStats computes per-type breakdown for one session only")
    func testSessionStatsComputesPerTypeBreakdown() async throws {
        let repo = InMemoryActivityLogRepository()
        let logger = ActivityLogger(repository: repo)
        let sid = UUID()
        let otherSid = UUID()

        let e1 = try await logger.createEntry(type: .stand, scheduledAt: .now, focusSessionId: sid)
        let e2 = try await logger.createEntry(type: .stand, scheduledAt: .now, focusSessionId: sid)
        let e3 = try await logger.createEntry(type: .water, scheduledAt: .now, focusSessionId: sid)
        // Noise: entry in a different session should not affect the result.
        _ = try await logger.createEntry(type: .stand, scheduledAt: .now, focusSessionId: otherSid)

        try await logger.recordResponse(for: e1.id, response: .completed)
        try await logger.recordResponse(for: e2.id, response: .missed)
        try await logger.recordResponse(for: e3.id, response: .completed)

        let stats = try await logger.sessionStats(for: sid)
        #expect(stats.totalReminders == 3)
        #expect(stats.totalCompleted == 2)
        #expect(stats.stats(for: .stand).complianceRate == 0.5)
        #expect(stats.stats(for: .water).complianceRate == 1.0)
    }

    @Test("Empty session (no logged entries) yields zero compliance")
    func testEmptySessionYieldsZero() async throws {
        let repo = InMemoryActivityLogRepository()
        let logger = ActivityLogger(repository: repo)
        let stats = try await logger.sessionStats(for: UUID())
        #expect(stats.totalReminders == 0)
        #expect(stats.overallComplianceRate == 0)
    }

    @Test("FocusSessionService.endSession persists stats onto the session record")
    func testEndSessionPersistsStats() async throws {
        let repo = InMemoryFocusSessionRepository()
        let service = FocusSessionService(repository: repo)
        let session = try await service.startSession()
        let stats = SessionStats(byType: [
            .stand: DailyStats.TypeStats(total: 2, completed: 1, skipped: 0, snoozed: 0, missed: 1)
        ])
        let ended = try await service.endSession(session.id, stats: stats)
        #expect(ended.stats?.totalReminders == 2)
        #expect(ended.stats?.totalCompleted == 1)
        // Reload from repo — stats must survive persistence
        let all = try await repo.allSessions()
        #expect(all.first(where: { $0.id == session.id })?.stats?.totalReminders == 2)
    }

    @Test("mostRecentEndedSession returns the latest by endedAt")
    func testMostRecentEndedSession() async throws {
        let repo = InMemoryFocusSessionRepository()
        let service = FocusSessionService(repository: repo)
        let now = Date.now
        let older = FocusSession(startedAt: now.addingTimeInterval(-7200),
                                  endedAt:   now.addingTimeInterval(-3600))
        let newer = FocusSession(startedAt: now.addingTimeInterval(-1800),
                                  endedAt:   now.addingTimeInterval(-600))
        try await repo.save([older, newer])
        let recent = try await service.mostRecentEndedSession()
        #expect(recent?.id == newer.id)
    }

    @Test("ActivityLogEntry without focusSessionId decodes from legacy JSON")
    func testLegacyJSONDecodesBackwardCompat() throws {
        // Legacy JSON shape — no focusSessionId field
        let legacyJSON = #"""
        {"id":"550e8400-e29b-41d4-a716-446655440000","type":"stand","scheduledAt":700000000,"deviceSource":"mac"}
        """#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ActivityLogEntry.self, from: legacyJSON)
        #expect(decoded.focusSessionId == nil)
        #expect(decoded.type == .stand)
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
            notifications: NoOpNotificationScheduler()
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

    // MARK: - Bug 1: first reminder must wait one full interval after focus start

    @Test("startFocusSession anchors lastFiredAt to the session start time")
    func testLastFiredAtAnchoredToSessionStart() async throws {
        let (engine, _) = await makeEngine()
        let before = Date.now
        await engine.startFocusSession(id: UUID())
        let after = Date.now
        for type in ReminderType.allCases {
            let lastFired = await engine.lastFiredAtForTest(type)
            #expect(lastFired != nil, "lastFiredAt should be set to session-start, not nil")
            if let lastFired {
                #expect(lastFired >= before && lastFired <= after,
                        "lastFiredAt should sit between the start window for \(type)")
            }
        }
    }

    @Test("First reminder does NOT fire on the heartbeat tick immediately after focus start")
    func testFirstReminderDoesNotFireImmediately() async throws {
        let (engine, repo) = await makeEngine()  // interval is 1 minute in scaffold
        await engine.startFocusSession(id: UUID())
        await engine.tickForTest()
        let entries = try await repo.recentLogs(limit: 50)
        #expect(entries.isEmpty,
                "No reminder should fire on the first tick — first fire must wait one full interval")
    }

    @Test("First reminder DOES fire once one full interval has elapsed since session start")
    func testFirstReminderFiresAfterFullInterval() async throws {
        let (engine, repo) = await makeEngine()  // interval is 1 minute
        await engine.startFocusSession(id: UUID())
        // Simulate the passage of (interval + 5s) for all reminder types
        let past = Date.now.addingTimeInterval(-65)
        for type in ReminderType.allCases {
            await engine.setLastFiredAtForTest(type, to: past)
        }
        await engine.tickForTest()
        let entries = try await repo.recentLogs(limit: 50)
        #expect(entries.count == ReminderType.allCases.count,
                "All enabled reminder types should fire once one full interval has elapsed")
    }
}

// MARK: - Bug 4: two-stage focus auto-exit

@Suite("Bug 4 — two-stage auto-exit on consecutive misses")
struct AutoExitTests {

    /// Engine + repo + notification stub. Returns the session id we'll associate entries with.
    private func makeEngine(sessionId: UUID = UUID()) async -> (
        engine: ReminderEngine,
        logRepo: InMemoryActivityLogRepository,
        scheduler: NoOpNotificationScheduler,
        sessionId: UUID
    ) {
        let logRepo = InMemoryActivityLogRepository()
        let logger = ActivityLogger(repository: logRepo)
        let scheduler = NoOpNotificationScheduler()
        let configs = ReminderType.allCases.map { type -> ReminderConfigData in
            var c = ReminderConfigData(type: type); c.intervalMinutes = 1; return c
        }
        let engine = ReminderEngine(
            configs: configs,
            profile: HealthProfileData(),
            logger: logger,
            notifications: scheduler
        )
        await engine.startFocusSession(id: sessionId)
        return (engine, logRepo, scheduler, sessionId)
    }

    /// Helper: inject a resolved log entry tagged with the active session, at a chosen time.
    private func injectEntry(
        into repo: InMemoryActivityLogRepository,
        sessionId: UUID,
        type: ReminderType,
        response: ActivityResponse,
        secondsAgo: TimeInterval
    ) async throws {
        let logger = ActivityLogger(repository: repo)
        let entry = try await logger.createEntry(
            type: type,
            scheduledAt: Date.now.addingTimeInterval(-secondsAgo),
            focusSessionId: sessionId
        )
        try await logger.recordResponse(for: entry.id, response: response)
    }

    @Test("One missed reminder does NOT trigger the check-in prompt")
    func testOneMissDoesNotTriggerCheckIn() async throws {
        let (engine, repo, scheduler, sid) = await makeEngine()
        try await injectEntry(into: repo, sessionId: sid, type: .stand, response: .missed, secondsAgo: 200)
        await engine.tickForTest()
        let checkIns = await scheduler.checkInIds
        #expect(checkIns.isEmpty)
        let count = await engine.consecutiveMissedCountForTest()
        #expect(count == 1)
    }

    @Test("Two consecutive missed reminders fire the 'Still focusing?' check-in")
    func testTwoMissesFireCheckIn() async throws {
        let (engine, repo, scheduler, sid) = await makeEngine()
        try await injectEntry(into: repo, sessionId: sid, type: .stand, response: .missed, secondsAgo: 600)
        try await injectEntry(into: repo, sessionId: sid, type: .water, response: .missed, secondsAgo: 300)
        await engine.tickForTest()
        let checkIns = await scheduler.checkInIds
        #expect(checkIns.count == 1, "Check-in prompt should fire exactly once at threshold")
        let promptFired = await engine.checkInPromptFiredForTest()
        #expect(promptFired)
    }

    @Test("Check-in prompt is not repeated across ticks while counter stays at 2")
    func testCheckInPromptNotRepeated() async throws {
        let (engine, repo, scheduler, sid) = await makeEngine()
        try await injectEntry(into: repo, sessionId: sid, type: .stand, response: .missed, secondsAgo: 600)
        try await injectEntry(into: repo, sessionId: sid, type: .water, response: .missed, secondsAgo: 300)
        await engine.tickForTest()
        await engine.tickForTest()
        await engine.tickForTest()
        let checkIns = await scheduler.checkInIds
        #expect(checkIns.count == 1, "Repeated ticks must not re-fire the check-in")
    }

    @Test("Three consecutive missed reminders trigger auto-end via callback")
    func testThreeMissesAutoEnd() async throws {
        let (engine, repo, _, sid) = await makeEngine()
        // Use an actor-isolated reference to capture the callback result safely.
        actor Box { var value: UUID? = nil; func set(_ id: UUID) { value = id } }
        let box = Box()
        await engine.setOnAutoEndRequested { id in await box.set(id) }

        try await injectEntry(into: repo, sessionId: sid, type: .stand, response: .missed, secondsAgo: 900)
        try await injectEntry(into: repo, sessionId: sid, type: .water, response: .missed, secondsAgo: 600)
        try await injectEntry(into: repo, sessionId: sid, type: .stretch, response: .missed, secondsAgo: 300)

        await engine.tickForTest()

        let captured = await box.value
        #expect(captured == sid, "Auto-end callback should fire with the active session id")
        let state = await engine.currentState
        if case .stopped = state { } else { Issue.record("Engine should be stopped after auto-end") }
    }

    @Test("Positive response (completed) between misses resets the counter")
    func testPositiveResponseResetsCounter() async throws {
        let (engine, repo, scheduler, sid) = await makeEngine()
        // Older: two misses, then one completed (most recent). Trailing run = 0.
        try await injectEntry(into: repo, sessionId: sid, type: .stand,   response: .missed,    secondsAgo: 900)
        try await injectEntry(into: repo, sessionId: sid, type: .water,   response: .missed,    secondsAgo: 600)
        try await injectEntry(into: repo, sessionId: sid, type: .stretch, response: .completed, secondsAgo: 60)

        await engine.tickForTest()

        let count = await engine.consecutiveMissedCountForTest()
        #expect(count == 0, "A completed response in the trailing window must reset the counter")
        let checkIns = await scheduler.checkInIds
        #expect(checkIns.isEmpty, "No check-in should fire when counter is reset")
    }

    @Test("acknowledgeStillFocusing clears counter and re-arms the check-in prompt")
    func testAcknowledgeStillFocusingResets() async throws {
        let (engine, repo, scheduler, sid) = await makeEngine()
        try await injectEntry(into: repo, sessionId: sid, type: .stand, response: .missed, secondsAgo: 600)
        try await injectEntry(into: repo, sessionId: sid, type: .water, response: .missed, secondsAgo: 300)
        await engine.tickForTest()  // Fires check-in #1

        await engine.acknowledgeStillFocusing()
        let countAfter = await engine.consecutiveMissedCountForTest()
        let firedAfter = await engine.checkInPromptFiredForTest()
        #expect(countAfter == 0)
        #expect(firedAfter == false)

        // Two more new misses → check-in should fire AGAIN (this is a fresh run).
        try await injectEntry(into: repo, sessionId: sid, type: .stand, response: .missed, secondsAgo: 100)
        try await injectEntry(into: repo, sessionId: sid, type: .water, response: .missed, secondsAgo: 50)
        await engine.tickForTest()
        let checkIns = await scheduler.checkInIds
        #expect(checkIns.count == 2, "Acknowledging then missing again should re-fire the prompt")
    }
}

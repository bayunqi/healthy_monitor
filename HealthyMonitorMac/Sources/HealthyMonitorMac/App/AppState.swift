import Foundation
import SwiftUI
import HealthyMonitorCore

/// Central observable state for the macOS app.
@MainActor
final class AppState: ObservableObject {
    @Published var profile: HealthProfileData = HealthProfileData()
    @Published var todayStats: DailyStats = .empty
    @Published var engineState: ReminderEngine.State = .stopped
    @Published var activeFocusSession: FocusSession? = nil
    @Published var isOnboarded: Bool = false
    /// Live compliance for the currently-active focus session. nil when no session active.
    @Published var currentSessionStats: SessionStats? = nil
    /// Most recently ended session — used by the menu bar idle state to show "Last session · X% · Yh ago".
    @Published var lastEndedSession: FocusSession? = nil

    private(set) var engine: ReminderEngine?
    private(set) var logger: ActivityLogger?
    private var profileService: HealthProfileService?
    private var focusSessionService: FocusSessionService?

    func bootstrap() async {
        let profileRepo = JSONFileHealthProfileRepository(
            fileURL: JSONFileHealthProfileRepository.defaultURL()
        )
        let profileSvc = HealthProfileService(repository: profileRepo)
        self.profileService = profileSvc

        let loadedProfile = (try? await profileSvc.currentProfile()) ?? HealthProfileData()
        self.profile = loadedProfile
        self.isOnboarded = loadedProfile.onboardingCompleted

        let logRepo = JSONFileActivityLogRepository(
            fileURL: JSONFileActivityLogRepository.defaultURL()
        )
        let activityLogger = ActivityLogger(repository: logRepo)
        self.logger = activityLogger

        // Focus session service — auto-end any orphaned session from previous launch
        let sessionRepo = JSONFileFocusSessionRepository(
            fileURL: JSONFileFocusSessionRepository.defaultURL()
        )
        let sessionSvc = FocusSessionService(repository: sessionRepo)
        self.focusSessionService = sessionSvc
        if let orphaned = try? await sessionSvc.activeSession() {
            // Compute final stats for the orphaned session before closing it out.
            let orphanedStats = try? await activityLogger.sessionStats(for: orphaned.id)
            _ = try? await sessionSvc.endSession(orphaned.id, stats: orphanedStats, reason: .endedByUser)
        }
        // Seed the idle UI with the most recent ended session.
        self.lastEndedSession = try? await sessionSvc.mostRecentEndedSession()

        let configs = ReminderType.allCases.map { type -> ReminderConfigData in
            var config = ReminderConfigData(type: type)
            if let stored = loadedProfile.reminderIntervalMinutes[type.rawValue] {
                config.intervalMinutes = stored
            }
            config.isEnabled = loadedProfile.isReminderEnabled(type)
            return config
        }
        let notif = NotificationService.shared
        let eng = ReminderEngine(
            configs: configs,
            profile: loadedProfile,
            logger: activityLogger,
            notifications: notif
        )
        self.engine = eng

        // Wire the engine's auto-end signal — engine has already cleared its own state
        // by the time this fires; the host just needs to persist + refresh the UI.
        await eng.setOnAutoEndRequested { [weak self] sessionId in
            await self?.handleAutoEnd(sessionId: sessionId)
        }
        await eng.start()

        await refreshStats()
    }

    func refreshStats() async {
        guard let logger else { return }
        todayStats = (try? await logger.dailyStats(for: .now)) ?? .empty
        if let activeId = activeFocusSession?.id {
            currentSessionStats = try? await logger.sessionStats(for: activeId)
        } else {
            currentSessionStats = nil
        }
    }

    func updateProfile(_ updated: HealthProfileData) async {
        profile = updated
        try? await profileService?.save(updated)
        await engine?.updateProfile(updated)
    }

    // MARK: - Focus session

    func startFocusSession() async {
        guard let svc = focusSessionService else { return }
        let session = try? await svc.startSession()
        activeFocusSession = session
        currentSessionStats = SessionStats.empty
        if let id = session?.id {
            await engine?.startFocusSession(id: id)
        }
        engineState = .running
    }

    func endFocusSession() async {
        guard let svc = focusSessionService, let session = activeFocusSession else { return }
        // Compute final compliance stats from session-tagged entries before persisting.
        let finalStats = try? await logger?.sessionStats(for: session.id)
        let ended = try? await svc.endSession(session.id, stats: finalStats, reason: .endedByUser)
        activeFocusSession = nil
        currentSessionStats = nil
        lastEndedSession = ended
        await engine?.endFocusSession()
        engineState = .stopped
        await updateLearnedFocusPattern(using: svc)
        await scheduleProactivePrompt(using: svc)
    }

    /// Invoked by ReminderEngine when it detects 3 consecutive missed reminders.
    /// Engine has already cleared its own session state; this method only handles persistence + UI.
    func handleAutoEnd(sessionId: UUID) async {
        guard let svc = focusSessionService else { return }
        let finalStats = try? await logger?.sessionStats(for: sessionId)
        let ended = try? await svc.endSession(sessionId, stats: finalStats, reason: .autoEndedDueToInactivity)
        activeFocusSession = nil
        currentSessionStats = nil
        lastEndedSession = ended
        engineState = .stopped
        await updateLearnedFocusPattern(using: svc)
        await scheduleProactivePrompt(using: svc)
    }

    /// User responded "Yes, still focusing" to the check-in prompt — reset the miss counter.
    func acknowledgeStillFocusing() async {
        await engine?.acknowledgeStillFocusing()
    }

    private func updateLearnedFocusPattern(using svc: FocusSessionService) async {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: .now)
        guard let hour = try? await svc.learnedStartHour(for: weekday) else { return }
        var updated = profile
        updated.learnedFocusStartHours[weekday] = hour
        await updateProfile(updated)
    }

    private func scheduleProactivePrompt(using svc: FocusSessionService) async {
        guard let fireDate = try? await svc.nextProactivePromptDate() else { return }
        try? await NotificationService.shared.scheduleProactivePrompt(at: fireDate)
    }

    // MARK: - Pause / resume within an active session

    func pauseEngine() async {
        await engine?.pause()
        engineState = .paused(until: nil)
    }

    func resumeEngine() async {
        await engine?.resume()
        engineState = .running
    }

    // MARK: - Settings

    func updateIntervals(stand: Int, water: Int, stretch: Int) async {
        var updated = profile
        updated.reminderIntervalMinutes[ReminderType.stand.rawValue] = stand
        updated.reminderIntervalMinutes[ReminderType.water.rawValue] = water
        updated.reminderIntervalMinutes[ReminderType.stretch.rawValue] = stretch
        await updateProfile(updated)
        await engine?.updateInterval(for: .stand, minutes: stand)
        await engine?.updateInterval(for: .water, minutes: water)
        await engine?.updateInterval(for: .stretch, minutes: stretch)
    }

    /// Toggle a reminder type on or off. Persisted to profile.json so the choice survives restarts.
    func setReminderEnabled(_ type: ReminderType, enabled: Bool) async {
        var updated = profile
        var map = updated.reminderEnabled ?? [:]
        map[type.rawValue] = enabled
        updated.reminderEnabled = map
        await updateProfile(updated)
        await engine?.setEnabled(for: type, enabled: enabled)
    }
}

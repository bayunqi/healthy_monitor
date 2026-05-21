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
            _ = try? await sessionSvc.endSession(orphaned.id)
        }

        let configs = ReminderType.allCases.map { type -> ReminderConfigData in
            var config = ReminderConfigData(type: type)
            if let stored = loadedProfile.reminderIntervalMinutes[type.rawValue] {
                config.intervalMinutes = stored
            }
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
        await eng.start()

        await refreshStats()
    }

    func refreshStats() async {
        guard let logger else { return }
        todayStats = (try? await logger.dailyStats(for: .now)) ?? .empty
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
        if let id = session?.id {
            await engine?.startFocusSession(id: id)
        }
        engineState = .running
    }

    func endFocusSession() async {
        guard let svc = focusSessionService, let session = activeFocusSession else { return }
        _ = try? await svc.endSession(session.id)
        activeFocusSession = nil
        await engine?.endFocusSession()
        engineState = .stopped
        await updateLearnedFocusPattern(using: svc)
        await scheduleProactivePrompt(using: svc)
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
}

import Foundation

/// Plain Codable data model. No SwiftData dependency in this package.
/// The app target wraps this in a @Model class for persistence.
public struct HealthProfileData: Codable, Sendable {
    public var userId: String
    public var displayName: String
    public var painPoints: [String]
    public var workScheduleStartHour: Int
    public var workScheduleEndHour: Int
    public var quietHoursStartHour: Int?
    public var quietHoursEndHour: Int?
    public var reminderStyle: ReminderStyle
    public var waterGoalMl: Int
    public var onboardingCompleted: Bool
    public var lastWeeklyPainScore: Int?
    public var conversationHistory: [LLMMessage]
    public var lastCoachingAt: Date?
    public var createdAt: Date
    public var profileVersion: Int
    public var reminderIntervalMinutes: [String: Int]
    public var learnedFocusStartHours: [Int: Int]

    public init(
        userId: String = UUID().uuidString,
        displayName: String = "",
        painPoints: [String] = [],
        workScheduleStartHour: Int = 9,
        workScheduleEndHour: Int = 18,
        quietHoursStartHour: Int? = nil,
        quietHoursEndHour: Int? = nil,
        reminderStyle: ReminderStyle = .gentle,
        waterGoalMl: Int = 2000,
        onboardingCompleted: Bool = false
    ) {
        self.userId = userId
        self.displayName = displayName
        self.painPoints = painPoints
        self.workScheduleStartHour = workScheduleStartHour
        self.workScheduleEndHour = workScheduleEndHour
        self.quietHoursStartHour = quietHoursStartHour
        self.quietHoursEndHour = quietHoursEndHour
        self.reminderStyle = reminderStyle
        self.waterGoalMl = waterGoalMl
        self.onboardingCompleted = onboardingCompleted
        self.conversationHistory = []
        self.createdAt = .now
        self.profileVersion = 1
        self.reminderIntervalMinutes = [:]
        self.learnedFocusStartHours = [:]
    }
}

import Foundation

/// Assembles the full DeepSeek API message array from profile + today's stats + history.
/// Always use this — never construct prompts inline.
public struct PromptBuilder {

    private static let coachingPersona = """
    You are HealthCoach, a warm and supportive personal health assistant for a programmer \
    who suffers from back and waist pain due to prolonged sitting.

    Your role:
    1. Build genuine understanding of their health situation through natural conversation.
    2. Remind them to take health breaks at the right moments.
    3. Celebrate small wins; when reminders are missed, respond with curiosity ("busy day?"), \
    never guilt or criticism.
    4. Provide evidence-based, practical health advice for desk workers.

    Tone: Collegial, warm, never preachy. Keep responses under 3 sentences unless the user \
    explicitly asks for more detail.
    """

    public static func buildMessages(
        profile: HealthProfileData,
        todayStats: DailyStats,
        conversationHistory: [LLMMessage],
        userMessage: String,
        focusContext: String? = nil
    ) -> [LLMMessage] {
        let systemContent = buildSystemContent(
            profile: profile,
            todayStats: todayStats,
            focusContext: focusContext
        )
        var messages: [LLMMessage] = [
            LLMMessage(role: .system, content: systemContent)
        ]
        // Keep last 10 exchanges to stay within context budget
        let recentHistory = Array(conversationHistory.suffix(10))
        messages.append(contentsOf: recentHistory)
        messages.append(LLMMessage(role: .user, content: userMessage))
        return messages
    }

    /// Builds the system content: persona + profile snapshot.
    /// This long prefix is eligible for DeepSeek's automatic disk cache.
    private static func buildSystemContent(
        profile: HealthProfileData,
        todayStats: DailyStats,
        focusContext: String? = nil
    ) -> String {
        let profileSnapshot = buildProfileSnapshot(profile: profile)
        let statsSnapshot = buildStatsSnapshot(todayStats)

        var result = """
        \(coachingPersona)

        ---
        CURRENT USER HEALTH PROFILE (version \(profile.profileVersion)):
        \(profileSnapshot)

        ---
        TODAY'S ACTIVITY SUMMARY (\(DateFormatter.shortDate.string(from: todayStats.date))):
        \(statsSnapshot)
        """
        if let focus = focusContext {
            result += "\n\n---\nFOCUS SESSION PATTERNS:\n\(focus)"
        }
        return result
    }

    private static func buildProfileSnapshot(profile: HealthProfileData) -> String {
        var lines: [String] = []
        if !profile.displayName.isEmpty {
            lines.append("Name: \(profile.displayName)")
        }
        if !profile.painPoints.isEmpty {
            lines.append("Pain points: \(profile.painPoints.joined(separator: ", "))")
        }
        lines.append("Work hours: \(profile.workScheduleStartHour):00 – \(profile.workScheduleEndHour):00")
        if let q0 = profile.quietHoursStartHour, let q1 = profile.quietHoursEndHour {
            lines.append("Quiet hours: \(q0):00 – \(q1):00 (no reminders)")
        }
        lines.append("Water goal: \(profile.waterGoalMl) ml/day")
        if let score = profile.lastWeeklyPainScore {
            lines.append("Last weekly pain score: \(score)/10")
        }
        return lines.joined(separator: "\n")
    }

    private static func buildStatsSnapshot(_ todayStats: DailyStats) -> String {
        guard todayStats.totalReminders > 0 else {
            return "No reminders scheduled yet today."
        }
        var lines: [String] = [
            "Overall compliance: \(Int(todayStats.overallComplianceRate * 100))% (\(todayStats.totalCompleted)/\(todayStats.totalReminders))"
        ]
        for type in ReminderType.allCases {
            let s = todayStats.stats(for: type)
            if s.total > 0 {
                lines.append("\(type.displayName): \(s.completed)/\(s.total) completed")
            }
        }
        return lines.joined(separator: "\n")
    }

    public static func onboardingSystemPrompt() -> String {
        """
        \(coachingPersona)

        You are currently conducting an onboarding conversation with a new user. \
        Your goal is to learn about them through natural conversation so you can personalize \
        their health reminder schedule. Ask about:
        - What physical symptoms or pain they experience (e.g., lower back, neck)
        - Their typical work hours
        - Whether they want quiet hours (no reminders during certain times)
        - Their water intake goal
        - Their preferred reminder style (gentle nudges vs firm reminders)
        - Any specific activities they want to be reminded about

        Ask one or two questions at a time. Be conversational, not form-like. \
        When you have enough information, use the update_health_profile tool to save it.
        """
    }
}

extension DateFormatter {
    static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
}

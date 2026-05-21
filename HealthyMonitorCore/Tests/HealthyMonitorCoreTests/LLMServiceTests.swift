import Testing
import Foundation
@testable import HealthyMonitorCore

@Suite("LLMService init")
struct LLMServiceInitTests {

    @Test("Throws missingAPIKey on empty string")
    func throwsOnEmptyKey() throws {
        #expect(throws: LLMError.missingAPIKey) {
            _ = try LLMService(apiKey: "")
        }
    }

    @Test("Initializes successfully with non-empty key")
    func initWithValidKey() throws {
        #expect(throws: Never.self) {
            _ = try LLMService(apiKey: "sk-test-key")
        }
    }
}

@Suite("LLMMessage")
struct LLMMessageTests {

    @Test("Encodes role and content correctly")
    func encodesCorrectly() throws {
        let msg = LLMMessage(role: .user, content: "hello")
        let data = try JSONEncoder().encode(msg)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(dict["role"] as? String == "user")
        #expect(dict["content"] as? String == "hello")
    }

    @Test("Round-trips through JSON")
    func roundTrip() throws {
        let original = LLMMessage(role: .assistant, content: "I can help!")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LLMMessage.self, from: data)
        #expect(decoded.role == .assistant)
        #expect(decoded.content == "I can help!")
    }

    @Test("System role encodes correctly")
    func systemRole() throws {
        let msg = LLMMessage(role: .system, content: "You are a health coach.")
        let data = try JSONEncoder().encode(msg)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(dict["role"] as? String == "system")
    }
}

@Suite("LLMTool")
struct LLMToolTests {

    @Test("updateHealthProfile has correct name")
    func updateProfileName() {
        #expect(LLMTool.updateHealthProfile.function.name == "update_health_profile")
    }

    @Test("adjustReminderSchedule has correct name")
    func adjustScheduleName() {
        #expect(LLMTool.adjustReminderSchedule.function.name == "adjust_reminder_schedule")
    }

    @Test("logObservation has correct name")
    func logObservationName() {
        #expect(LLMTool.logObservation.function.name == "log_observation")
    }

    @Test("coachingTools contains exactly 3 tools")
    func coachingToolsCount() {
        #expect(LLMTool.coachingTools.count == 3)
    }

    @Test("Tool encodes to valid JSON with type='function'")
    func encodes() throws {
        let data = try JSONEncoder().encode(LLMTool.updateHealthProfile)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(dict["type"] as? String == "function")
        let fn = dict["function"] as? [String: Any]
        #expect(fn?["name"] as? String == "update_health_profile")
    }

    @Test("adjustReminderSchedule interval properties exist in schema")
    func adjustScheduleSchema() throws {
        let data = try JSONEncoder().encode(LLMTool.adjustReminderSchedule)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let fn = dict["function"] as! [String: Any]
        let params = fn["parameters"] as! [String: Any]
        let props = params["properties"] as! [String: Any]
        #expect(props["standIntervalMinutes"] != nil)
        #expect(props["waterIntervalMinutes"] != nil)
        #expect(props["stretchIntervalMinutes"] != nil)
    }
}

@Suite("PromptBuilder")
struct PromptBuilderTests {

    @Test("buildMessages produces system + user when no history")
    func noHistory() {
        let profile = HealthProfileData()
        let messages = PromptBuilder.buildMessages(
            profile: profile,
            todayStats: .empty,
            conversationHistory: [],
            userMessage: "Hello"
        )
        #expect(messages.count == 2)
        #expect(messages[0].role == .system)
        #expect(messages[1].role == .user)
        #expect(messages[1].content == "Hello")
    }

    @Test("System message contains 'HealthCoach'")
    func containsPersona() {
        let messages = PromptBuilder.buildMessages(
            profile: HealthProfileData(),
            todayStats: .empty,
            conversationHistory: [],
            userMessage: "Hi"
        )
        #expect(messages[0].content.contains("HealthCoach"))
    }

    @Test("History is capped at 10 messages")
    func historyCapped() {
        let history = (0..<20).map {
            LLMMessage(role: $0 % 2 == 0 ? .user : .assistant, content: "msg \($0)")
        }
        let messages = PromptBuilder.buildMessages(
            profile: HealthProfileData(),
            todayStats: .empty,
            conversationHistory: history,
            userMessage: "latest"
        )
        // 1 system + 10 history + 1 user = 12
        #expect(messages.count == 12)
    }

    @Test("Profile version appears in system message for cache invalidation")
    func profileVersionInSystem() {
        var profile = HealthProfileData()
        profile.profileVersion = 99
        let messages = PromptBuilder.buildMessages(
            profile: profile,
            todayStats: .empty,
            conversationHistory: [],
            userMessage: "test"
        )
        #expect(messages[0].content.contains("99"))
    }

    @Test("Pain points appear in system message")
    func painPointsInSystem() {
        var profile = HealthProfileData()
        profile.painPoints = ["lower back", "wrists"]
        let messages = PromptBuilder.buildMessages(
            profile: profile,
            todayStats: .empty,
            conversationHistory: [],
            userMessage: "hi"
        )
        let sys = messages[0].content
        #expect(sys.contains("lower back"))
        #expect(sys.contains("wrists"))
    }

    @Test("Onboarding system prompt contains onboarding-specific instructions")
    func onboardingPrompt() {
        let prompt = PromptBuilder.onboardingSystemPrompt()
        #expect(prompt.contains("onboarding"))
        #expect(prompt.contains("update_health_profile"))
    }
}

@Suite("HealthProfileService (in-memory)")
struct HealthProfileServiceTests {

    @Test("Returns default profile when none saved")
    func defaultProfile() async throws {
        let repo = InMemoryHealthProfileRepository()
        let service = HealthProfileService(repository: repo)
        let profile = try await service.currentProfile()
        #expect(!profile.onboardingCompleted)
        #expect(profile.painPoints.isEmpty)
    }

    @Test("Save and reload persists changes")
    func saveAndReload() async throws {
        let repo = InMemoryHealthProfileRepository()
        let service = HealthProfileService(repository: repo)
        var profile = try await service.currentProfile()
        profile.painPoints = ["neck"]
        try await service.save(profile)

        let fresh = HealthProfileService(repository: repo)
        let loaded = try await fresh.currentProfile()
        #expect(loaded.painPoints == ["neck"])
    }

    @Test("appendMessage keeps history capped at 50")
    func historyCap() async throws {
        let repo = InMemoryHealthProfileRepository()
        let service = HealthProfileService(repository: repo)
        for i in 0..<55 {
            try await service.appendMessage(LLMMessage(role: .user, content: "msg \(i)"))
        }
        let profile = try await service.currentProfile()
        #expect(profile.conversationHistory.count == 50)
    }

    @Test("applyProfileUpdate increments profileVersion")
    func profileVersionIncrement() async throws {
        let repo = InMemoryHealthProfileRepository()
        let service = HealthProfileService(repository: repo)
        let before = try await service.currentProfile()
        let v0 = before.profileVersion
        try await service.applyProfileUpdate(["painPoints": ["lower back"] as Any])
        let after = try await service.currentProfile()
        #expect(after.profileVersion == v0 + 1)
        #expect(after.painPoints == ["lower back"])
    }
}

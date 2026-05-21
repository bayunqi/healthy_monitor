import Foundation

// MARK: - Repository protocol

public protocol HealthProfileRepository: Sendable {
    func load() async throws -> HealthProfileData
    func save(_ profile: HealthProfileData) async throws
}

// MARK: - In-memory implementation (tests / preview)

public actor InMemoryHealthProfileRepository: HealthProfileRepository {
    private var profile: HealthProfileData

    public init(profile: HealthProfileData = HealthProfileData()) {
        self.profile = profile
    }

    public func load() async throws -> HealthProfileData { profile }
    public func save(_ profile: HealthProfileData) async throws { self.profile = profile }
}

// MARK: - JSON file implementation (MVP persistence without SwiftData)

public actor JSONFileHealthProfileRepository: HealthProfileRepository {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func defaultURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("HealthyMonitor", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("profile.json")
    }

    public func load() async throws -> HealthProfileData {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return HealthProfileData()
        }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(HealthProfileData.self, from: data)
    }

    public func save(_ profile: HealthProfileData) async throws {
        let data = try encoder.encode(profile)
        try data.write(to: fileURL, options: .atomic)
    }
}

// MARK: - Service

public actor HealthProfileService {
    private let repository: any HealthProfileRepository
    private var cached: HealthProfileData?

    public init(repository: any HealthProfileRepository) {
        self.repository = repository
    }

    public func currentProfile() async throws -> HealthProfileData {
        if let cached { return cached }
        let loaded = try await repository.load()
        cached = loaded
        return loaded
    }

    public func save(_ profile: HealthProfileData) async throws {
        cached = profile
        try await repository.save(profile)
    }

    // MARK: - Conversation history

    private let maxHistoryMessages = 50

    public func appendMessage(_ message: LLMMessage) async throws {
        var profile = try await currentProfile()
        profile.conversationHistory.append(message)
        if profile.conversationHistory.count > maxHistoryMessages {
            profile.conversationHistory = Array(profile.conversationHistory.suffix(maxHistoryMessages))
        }
        try await save(profile)
    }

    // MARK: - LLM tool call handlers

    public func applyProfileUpdate(_ args: [String: Any]) async throws {
        var profile = try await currentProfile()
        if let points = args["painPoints"] as? [String] { profile.painPoints = points }
        if let start = args["workScheduleStartHour"] as? Int { profile.workScheduleStartHour = start }
        if let end = args["workScheduleEndHour"] as? Int { profile.workScheduleEndHour = end }
        if let water = args["waterGoalMl"] as? Int { profile.waterGoalMl = water }
        if let raw = args["reminderStyle"] as? String,
           let style = ReminderStyle(rawValue: raw) { profile.reminderStyle = style }
        profile.profileVersion += 1
        try await save(profile)
    }

    public func parseScheduleAdjustment(_ args: [String: Any]) -> [ReminderType: Int] {
        var result: [ReminderType: Int] = [:]
        if let m = args["standIntervalMinutes"] as? Int { result[.stand] = m }
        if let m = args["waterIntervalMinutes"] as? Int { result[.water] = m }
        if let m = args["stretchIntervalMinutes"] as? Int { result[.stretch] = m }
        return result
    }
}

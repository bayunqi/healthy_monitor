import Foundation

// MARK: - Repository protocol

public protocol FocusSessionRepository: Sendable {
    func createSession() async throws -> FocusSession
    func endSession(_ id: UUID, at date: Date) async throws -> FocusSession
    func allSessions() async throws -> [FocusSession]
    func save(_ sessions: [FocusSession]) async throws
}

// MARK: - In-memory implementation (tests)

public actor InMemoryFocusSessionRepository: FocusSessionRepository {
    private var sessions: [UUID: FocusSession] = [:]

    public init() {}

    public func createSession() async throws -> FocusSession {
        let session = FocusSession()
        sessions[session.id] = session
        return session
    }

    public func endSession(_ id: UUID, at date: Date) async throws -> FocusSession {
        guard sessions[id] != nil else { throw FocusSessionError.sessionNotFound }
        sessions[id]?.endedAt = date
        return sessions[id]!
    }

    public func allSessions() async throws -> [FocusSession] {
        Array(sessions.values).sorted { $0.startedAt < $1.startedAt }
    }

    public func save(_ sessions: [FocusSession]) async throws {
        self.sessions = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
    }
}

// MARK: - JSON file implementation

public actor JSONFileFocusSessionRepository: FocusSessionRepository {
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
        return dir.appendingPathComponent("focussessions.json")
    }

    public func createSession() async throws -> FocusSession {
        var all = (try? await allSessions()) ?? []
        let session = FocusSession()
        all.append(session)
        try await persist(all)
        return session
    }

    public func endSession(_ id: UUID, at date: Date) async throws -> FocusSession {
        var all = try await allSessions()
        guard let idx = all.firstIndex(where: { $0.id == id }) else {
            throw FocusSessionError.sessionNotFound
        }
        all[idx].endedAt = date
        try await persist(all)
        return all[idx]
    }

    public func allSessions() async throws -> [FocusSession] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([FocusSession].self, from: data)
    }

    public func save(_ sessions: [FocusSession]) async throws {
        try await persist(sessions)
    }

    private func persist(_ sessions: [FocusSession]) async throws {
        let data = try encoder.encode(sessions)
        try data.write(to: fileURL, options: .atomic)
    }
}

// MARK: - Error

public enum FocusSessionError: Error, LocalizedError, Sendable {
    case sessionNotFound
    case noActiveSession

    public var errorDescription: String? {
        switch self {
        case .sessionNotFound: return "Focus session not found."
        case .noActiveSession: return "No active focus session."
        }
    }
}

// MARK: - Service

public actor FocusSessionService {
    private let repository: any FocusSessionRepository

    public init(repository: any FocusSessionRepository) {
        self.repository = repository
    }

    // MARK: - Session lifecycle

    public func startSession() async throws -> FocusSession {
        try await repository.createSession()
    }

    public func endSession(_ id: UUID) async throws -> FocusSession {
        try await repository.endSession(id, at: .now)
    }

    public func activeSession() async throws -> FocusSession? {
        let all = try await repository.allSessions()
        return all.first(where: { $0.isActive })
    }

    public func recentSessions(limit: Int = 10) async throws -> [FocusSession] {
        let all = try await repository.allSessions()
        return Array(all.sorted { $0.startedAt > $1.startedAt }.prefix(limit))
    }

    // MARK: - Pattern learning

    /// Returns the median start hour for sessions on the given weekday (1=Sun...7=Sat).
    /// Requires at least 3 completed sessions on that weekday; returns nil otherwise.
    public func learnedStartHour(for weekday: Int) async throws -> Int? {
        let all = try await repository.allSessions()
        let calendar = Calendar.current
        let hours = all
            .filter { !$0.isActive && calendar.component(.weekday, from: $0.startedAt) == weekday }
            .suffix(10)
            .map { calendar.component(.hour, from: $0.startedAt) }
            .sorted()
        guard hours.count >= 3 else { return nil }
        return hours[hours.count / 2]
    }

    /// Returns the next fire date for a proactive focus prompt based on the learned start hour.
    /// Returns nil if fewer than 3 sessions exist for today's weekday.
    public func nextProactivePromptDate() async throws -> Date? {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: .now)
        guard let hour = try await learnedStartHour(for: weekday) else { return nil }

        var components = calendar.dateComponents([.year, .month, .day], from: .now)
        components.hour = hour
        components.minute = 0
        components.second = 0
        guard var fireDate = calendar.date(from: components) else { return nil }

        if fireDate <= Date.now {
            // Already past today — schedule for next same weekday (7 days later)
            fireDate = calendar.date(byAdding: .day, value: 7, to: fireDate) ?? fireDate
        }
        return fireDate
    }

    // MARK: - AI coach context

    /// A one-liner for the coaching system prompt about session patterns.
    public func focusContextString(recentCount: Int = 7) async throws -> String? {
        let sessions = try await recentSessions(limit: recentCount)
        let completed = sessions.filter { !$0.isActive }
        guard !completed.isEmpty else { return nil }

        let avgSeconds = completed.compactMap(\.duration).reduce(0, +) / Double(completed.count)
        let h = Int(avgSeconds) / 3600
        let m = (Int(avgSeconds) % 3600) / 60
        let durationStr = h > 0 ? "\(h)h \(m)m" : "\(m)m"
        return "Recent focus sessions: \(completed.count) in the last week, avg duration \(durationStr)."
    }
}

import Foundation

/// JSON file-based activity log repository. Suitable for MVP single-user use.
/// The app target can swap this for a SwiftData implementation when Xcode is available.
public actor JSONFileActivityLogRepository: ActivityLogRepository {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var cache: [UUID: ActivityLogEntry]?

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func defaultURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("HealthyMonitor", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("activitylog.json")
    }

    public func createEntry(type: ReminderType, scheduledAt: Date, deviceSource: String = "mac", focusSessionId: UUID? = nil) async throws -> ActivityLogEntry {
        var store = try await loadStore()
        let entry = ActivityLogEntry(type: type, scheduledAt: scheduledAt, deviceSource: deviceSource, focusSessionId: focusSessionId)
        store[entry.id] = entry
        try await persist(store)
        return entry
    }

    public func recordResponse(for id: UUID, response: ActivityResponse) async throws {
        var store = try await loadStore()
        guard store[id] != nil else { return }
        store[id]?.response = response
        store[id]?.respondedAt = .now
        try await persist(store)
    }

    public func markStaleMissed(gracePeriodMinutes: Int = 5) async throws {
        let cutoff = Date.now.addingTimeInterval(-TimeInterval(gracePeriodMinutes * 60))
        var store = try await loadStore()
        var changed = false
        for id in store.keys where store[id]?.response == nil {
            if let scheduledAt = store[id]?.scheduledAt, scheduledAt < cutoff {
                store[id]?.response = .missed
                store[id]?.respondedAt = .now
                changed = true
            }
        }
        if changed { try await persist(store) }
    }

    public func logs(from: Date, to: Date) async throws -> [ActivityLogEntry] {
        let store = try await loadStore()
        return store.values
            .filter { $0.scheduledAt >= from && $0.scheduledAt <= to }
            .sorted { $0.scheduledAt < $1.scheduledAt }
    }

    public func logs(for sessionId: UUID) async throws -> [ActivityLogEntry] {
        let store = try await loadStore()
        return store.values
            .filter { $0.focusSessionId == sessionId }
            .sorted { $0.scheduledAt < $1.scheduledAt }
    }

    public func recentLogs(limit: Int = 50) async throws -> [ActivityLogEntry] {
        let store = try await loadStore()
        return Array(store.values.sorted { $0.scheduledAt > $1.scheduledAt }.prefix(limit))
    }

    // MARK: - Private

    private func loadStore() async throws -> [UUID: ActivityLogEntry] {
        if let cached = cache { return cached }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [:] }
        let data = try Data(contentsOf: fileURL)
        let array = try decoder.decode([ActivityLogEntry].self, from: data)
        let store = Dictionary(uniqueKeysWithValues: array.map { ($0.id, $0) })
        cache = store
        return store
    }

    private func persist(_ store: [UUID: ActivityLogEntry]) async throws {
        cache = store
        let array = Array(store.values)
        let data = try encoder.encode(array)
        try data.write(to: fileURL, options: .atomic)
    }
}

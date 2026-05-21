import Foundation

// MARK: - Message types

public struct LLMMessage: Codable, Sendable {
    public enum Role: String, Codable, Sendable {
        case system, user, assistant, tool
    }

    public let role: Role
    public let content: String
    public let toolCallId: String?   // only for role == .tool (tool result messages)
    public let toolCalls: [LLMToolCall]?  // only for role == .assistant with tool calls

    public init(role: Role, content: String, toolCallId: String? = nil, toolCalls: [LLMToolCall]? = nil) {
        self.role = role
        self.content = content
        self.toolCallId = toolCallId
        self.toolCalls = toolCalls
    }

    enum CodingKeys: String, CodingKey {
        case role, content
        case toolCallId  = "tool_call_id"
        case toolCalls   = "tool_calls"
    }
}

public struct LLMToolCall: Codable, Sendable {
    public let id: String
    public let type: String
    public let function: LLMFunctionCall

    public struct LLMFunctionCall: Codable, Sendable {
        public let name: String
        public let arguments: String  // JSON string
    }
}

// MARK: - Tool definitions

public struct LLMTool: Encodable, Sendable {
    public let type: String = "function"
    public let function: ToolFunction

    public struct ToolFunction: Encodable, Sendable {
        public let name: String
        public let description: String
        public let parameters: ToolParameters
    }

    public struct ToolParameters: Encodable, Sendable {
        public let type: String = "object"
        public let properties: [String: ToolProperty]
        public let required: [String]

        public struct ToolProperty: Encodable, Sendable {
            public let type: String
            public let description: String
            public let enumValues: [String]?

            enum CodingKeys: String, CodingKey {
                case type, description
                case enumValues = "enum"
            }
        }
    }
}

// MARK: - API request / response

private struct DeepSeekRequest: Encodable {
    let model: String
    let messages: [LLMMessage]
    let tools: [LLMTool]?
    let temperature: Double
    let maxTokens: Int
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model, messages, tools, temperature, stream
        case maxTokens = "max_tokens"
    }
}

private struct DeepSeekResponse: Decodable {
    let id: String
    let choices: [Choice]
    let usage: Usage?

    struct Choice: Decodable {
        let message: ChoiceMessage
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
        }

        struct ChoiceMessage: Decodable {
            let role: String
            let content: String?
            let toolCalls: [LLMToolCall]?

            enum CodingKeys: String, CodingKey {
                case role, content
                case toolCalls = "tool_calls"
            }
        }
    }

    struct Usage: Decodable {
        let promptTokens: Int
        let completionTokens: Int
        let promptCacheHitTokens: Int?
        let promptCacheMissTokens: Int?

        enum CodingKeys: String, CodingKey {
            case promptTokens          = "prompt_tokens"
            case completionTokens      = "completion_tokens"
            case promptCacheHitTokens  = "prompt_cache_hit_tokens"
            case promptCacheMissTokens = "prompt_cache_miss_tokens"
        }
    }
}

// MARK: - Result

public struct LLMResponse: Sendable {
    public let content: String?
    public let toolCalls: [LLMToolCall]
    public let cacheHitTokens: Int
    public let cacheMissTokens: Int

    public var hasToolCalls: Bool { !toolCalls.isEmpty }
}

// MARK: - Error

public enum LLMError: Error, LocalizedError, Sendable, Equatable {
    case missingAPIKey
    case httpError(statusCode: Int, body: String)
    case decodingError(String)
    case emptyResponse

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "DeepSeek API key not configured. Set DEEPSEEK_API_KEY."
        case let .httpError(code, body):
            return "DeepSeek API HTTP \(code): \(body)"
        case let .decodingError(msg):
            return "Failed to decode DeepSeek response: \(msg)"
        case .emptyResponse:
            return "DeepSeek returned an empty response."
        }
    }
}

// MARK: - Service

public actor LLMService {
    private let apiKey: String
    private let baseURL = URL(string: "https://api.deepseek.com/v1/chat/completions")!
    private let model = "deepseek-chat"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let session: URLSession

    public init(apiKey: String) throws {
        guard !apiKey.isEmpty else { throw LLMError.missingAPIKey }
        self.apiKey = apiKey
        self.session = URLSession(configuration: .default)
    }

    /// Send a chat completion request to DeepSeek.
    public func send(messages: [LLMMessage], tools: [LLMTool]? = nil) async throws -> LLMResponse {
        let body = DeepSeekRequest(
            model: model,
            messages: messages,
            tools: tools?.isEmpty == false ? tools : nil,
            temperature: 0.7,
            maxTokens: 512,
            stream: false
        )
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw LLMError.httpError(statusCode: 0, body: "no HTTP response")
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            throw LLMError.httpError(statusCode: http.statusCode, body: body)
        }

        let parsed: DeepSeekResponse
        do {
            parsed = try decoder.decode(DeepSeekResponse.self, from: data)
        } catch {
            throw LLMError.decodingError(error.localizedDescription)
        }

        guard let choice = parsed.choices.first else {
            throw LLMError.emptyResponse
        }

        return LLMResponse(
            content: choice.message.content,
            toolCalls: choice.message.toolCalls ?? [],
            cacheHitTokens: parsed.usage?.promptCacheHitTokens ?? 0,
            cacheMissTokens: parsed.usage?.promptCacheMissTokens ?? 0
        )
    }
}

// MARK: - Built-in tools

public extension LLMTool {
    static let updateHealthProfile = LLMTool(
        function: .init(
            name: "update_health_profile",
            description: "Save information learned about the user's health situation to their profile.",
            parameters: .init(
                properties: [
                    "painPoints": .init(type: "array", description: "Body areas with pain, e.g. [\"lower back\", \"neck\"]", enumValues: nil),
                    "workScheduleStartHour": .init(type: "integer", description: "Work start hour (0–23)", enumValues: nil),
                    "workScheduleEndHour": .init(type: "integer", description: "Work end hour (0–23)", enumValues: nil),
                    "waterGoalMl": .init(type: "integer", description: "Daily water goal in milliliters", enumValues: nil),
                    "reminderStyle": .init(type: "string", description: "Reminder style preference", enumValues: ["gentle", "firm", "silentOnlyWatch"])
                ],
                required: []
            )
        )
    )

    static let adjustReminderSchedule = LLMTool(
        function: .init(
            name: "adjust_reminder_schedule",
            description: "Adjust reminder intervals based on compliance patterns or user preference.",
            parameters: .init(
                properties: [
                    "standIntervalMinutes": .init(type: "integer", description: "Stand reminder interval (15–120 min)", enumValues: nil),
                    "waterIntervalMinutes": .init(type: "integer", description: "Water reminder interval (15–120 min)", enumValues: nil),
                    "stretchIntervalMinutes": .init(type: "integer", description: "Stretch reminder interval (15–120 min)", enumValues: nil),
                    "quietHoursStartHour": .init(type: "integer", description: "Quiet hours start (0–23)", enumValues: nil),
                    "quietHoursEndHour": .init(type: "integer", description: "Quiet hours end (0–23)", enumValues: nil)
                ],
                required: []
            )
        )
    )

    static let logObservation = LLMTool(
        function: .init(
            name: "log_observation",
            description: "Record a coaching observation about the user's behavior or health trend.",
            parameters: .init(
                properties: [
                    "observation": .init(type: "string", description: "The observation text", enumValues: nil),
                    "category": .init(type: "string", description: "Observation category", enumValues: ["compliance", "pain", "improvement", "concern"]),
                    "severity": .init(type: "string", description: "Severity level", enumValues: ["info", "warning", "action_needed"])
                ],
                required: ["observation", "category", "severity"]
            )
        )
    )

    static var coachingTools: [LLMTool] {
        [updateHealthProfile, adjustReminderSchedule, logObservation]
    }
}

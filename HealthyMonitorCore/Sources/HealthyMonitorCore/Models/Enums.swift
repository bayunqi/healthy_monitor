import Foundation

public enum ReminderType: String, Codable, CaseIterable, Sendable {
    case stand   = "stand"
    case water   = "water"
    case stretch = "stretch"

    public var displayName: String {
        switch self {
        case .stand:   return "Stand Up"
        case .water:   return "Drink Water"
        case .stretch: return "Stretch"
        }
    }

    public var emoji: String {
        switch self {
        case .stand:   return "🧍"
        case .water:   return "💧"
        case .stretch: return "🤸"
        }
    }

    /// Default interval in minutes for first-time setup
    public var defaultIntervalMinutes: Int {
        switch self {
        case .stand:   return 45
        case .water:   return 90
        case .stretch: return 60
        }
    }
}

public enum ActivityResponse: String, Codable, Sendable {
    case completed = "completed"
    case skipped   = "skipped"
    case snoozed   = "snoozed"
    case missed    = "missed"
}

public enum ReminderStyle: String, Codable, Sendable {
    case gentle           // sound + banner
    case firm             // sound + banner + badge
    case silentOnlyWatch  // no Mac/iPhone notification; Watch only
}

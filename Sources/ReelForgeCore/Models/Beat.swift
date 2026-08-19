import Foundation

public enum BeatRole: Codable, Equatable, Sendable {
    case hook
    case body(Int)
    case cta

    public var label: String {
        switch self {
        case .hook: return "Hook"
        case .body(let i): return "Beat \(i + 1)"
        case .cta: return "CTA"
        }
    }

    public var edlName: String {
        switch self {
        case .hook: return "hook"
        case .body: return "body"
        case .cta: return "cta"
        }
    }
}

public struct Beat: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var index: Int
    public var role: BeatRole
    public var text: String
    public var start: Double
    public var duration: Double
    public var unsplashQuery: String
    public var stepNumber: Int?

    public init(
        id: String,
        index: Int,
        role: BeatRole,
        text: String,
        start: Double,
        duration: Double,
        unsplashQuery: String,
        stepNumber: Int? = nil
    ) {
        self.id = id
        self.index = index
        self.role = role
        self.text = text
        self.start = start
        self.duration = duration
        self.unsplashQuery = unsplashQuery
        self.stepNumber = stepNumber
    }

    public var end: Double { start + duration }
}

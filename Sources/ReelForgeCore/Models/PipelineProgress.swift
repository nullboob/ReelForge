import Foundation

public enum PipelineStep: String, CaseIterable, Codable, Sendable {
    case script
    case storyboard
    case voice
    case captions
    case footage
    case music
    case compose
    case package
    case export

    public var title: String {
        switch self {
        case .script: return "Script"
        case .storyboard: return "Storyboard"
        case .voice: return "Voice"
        case .captions: return "Captions"
        case .footage: return "Footage"
        case .music: return "Music"
        case .compose: return "Compose"
        case .package: return "Publish pack"
        case .export: return "Export"
        }
    }

    public var defaultDetail: String {
        switch self {
        case .script: return "Writing hook, body, and CTA"
        case .storyboard: return "Timing beats to the preset pace"
        case .voice: return "Preparing voiceover"
        case .captions: return "Building word-timed caption cards"
        case .footage: return "Collecting B-roll and styled cards"
        case .music: return "Scoring a ducked music bed"
        case .compose: return "Laying the timeline, grade, and transitions"
        case .package: return "Title, description, chapters, thumbnail, SRT"
        case .export: return "Writing H.264 MP4"
        }
    }
}

public struct PipelineProgress: Equatable, Sendable {
    public var current: PipelineStep?
    public var completed: [PipelineStep]
    public var detail: String
    public var fraction: Double
    public var isFinished: Bool
    public var isFailed: Bool

    public init(
        current: PipelineStep? = nil,
        completed: [PipelineStep] = [],
        detail: String = "",
        fraction: Double = 0,
        isFinished: Bool = false,
        isFailed: Bool = false
    ) {
        self.current = current
        self.completed = completed
        self.detail = detail
        self.fraction = fraction
        self.isFinished = isFinished
        self.isFailed = isFailed
    }

    public static let idle = PipelineProgress(detail: "Type a topic, pick a preset, generate.")

    public func isDone(_ step: PipelineStep) -> Bool {
        completed.contains(step)
    }
}

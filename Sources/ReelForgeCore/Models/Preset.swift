import Foundation

public enum TransitionType: String, Codable, CaseIterable, Sendable {
    case hardCut
    case fade
    case zoom
    case whip
}

public enum CaptionPosition: String, Codable, CaseIterable, Sendable {
    case center
    case bottom
}

public enum CaptionAnimation: String, Codable, CaseIterable, Sendable {
    case pop
    case wordByWord = "word-by-word"
    case karaoke
}

public enum MusicMood: String, Codable, CaseIterable, Sendable {
    case pulse
    case cinematic
    case clean
    case warm
}

public struct Pace: Codable, Equatable, Sendable {
    public var cutMinSec: Double
    public var cutMaxSec: Double
    public var transition: TransitionType

    public init(cutMinSec: Double, cutMaxSec: Double, transition: TransitionType) {
        self.cutMinSec = cutMinSec
        self.cutMaxSec = cutMaxSec
        self.transition = transition
    }

    public var averageCut: Double { (cutMinSec + cutMaxSec) / 2 }
}

public struct CaptionStyle: Codable, Equatable, Sendable {
    public var font: String
    public var size: Double
    public var weight: String
    public var fill: String
    public var stroke: String
    public var highlight: String
    public var position: CaptionPosition
    public var maxWordsPerCard: Int
    public var animation: CaptionAnimation

    public init(
        font: String,
        size: Double,
        weight: String,
        fill: String,
        stroke: String,
        highlight: String,
        position: CaptionPosition,
        maxWordsPerCard: Int,
        animation: CaptionAnimation
    ) {
        self.font = font
        self.size = size
        self.weight = weight
        self.fill = fill
        self.stroke = stroke
        self.highlight = highlight
        self.position = position
        self.maxWordsPerCard = maxWordsPerCard
        self.animation = animation
    }
}

public struct TitleCardStyle: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var font: String
    public var size: Double
    public var fill: String
    public var background: String
    public var numbered: Bool

    public init(
        enabled: Bool,
        font: String,
        size: Double,
        fill: String,
        background: String,
        numbered: Bool
    ) {
        self.enabled = enabled
        self.font = font
        self.size = size
        self.fill = fill
        self.background = background
        self.numbered = numbered
    }
}

public struct ColorGrade: Codable, Equatable, Sendable {
    public var contrast: Double
    public var saturation: Double
    public var warmth: Double
    public var vignette: Double

    public init(contrast: Double, saturation: Double, warmth: Double, vignette: Double) {
        self.contrast = contrast
        self.saturation = saturation
        self.warmth = warmth
        self.vignette = vignette
    }
}

public struct MusicStyle: Codable, Equatable, Sendable {
    public var mood: MusicMood
    public var bpm: Int
    public var duckDb: Double

    public init(mood: MusicMood, bpm: Int, duckDb: Double) {
        self.mood = mood
        self.bpm = bpm
        self.duckDb = duckDb
    }

    public var duckLinear: Double {
        pow(10.0, duckDb / 20.0)
    }
}

public struct FootageStyle: Codable, Equatable, Sendable {
    public var unsplashQueries: [String]
    public var kenBurns: Bool
    public var zoomPulse: Bool
    public var overlayGrain: Bool

    public init(unsplashQueries: [String], kenBurns: Bool, zoomPulse: Bool, overlayGrain: Bool) {
        self.unsplashQueries = unsplashQueries
        self.kenBurns = kenBurns
        self.zoomPulse = zoomPulse
        self.overlayGrain = overlayGrain
    }
}

public struct Preset: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var tagline: String
    public var coverGradient: [String]
    public var aspect: AspectRatio
    public var durationSec: Int
    public var pace: Pace
    public var captionStyle: CaptionStyle
    public var titleCard: TitleCardStyle
    public var colorGrade: ColorGrade
    public var music: MusicStyle
    public var footage: FootageStyle
    public var aiImageStyleSuffix: String
    public var aiVideoEnabled: Bool

    public init(
        id: String,
        name: String,
        tagline: String,
        coverGradient: [String],
        aspect: AspectRatio,
        durationSec: Int,
        pace: Pace,
        captionStyle: CaptionStyle,
        titleCard: TitleCardStyle,
        colorGrade: ColorGrade,
        music: MusicStyle,
        footage: FootageStyle,
        aiImageStyleSuffix: String,
        aiVideoEnabled: Bool
    ) {
        self.id = id
        self.name = name
        self.tagline = tagline
        self.coverGradient = coverGradient
        self.aspect = aspect
        self.durationSec = durationSec
        self.pace = pace
        self.captionStyle = captionStyle
        self.titleCard = titleCard
        self.colorGrade = colorGrade
        self.music = music
        self.footage = footage
        self.aiImageStyleSuffix = aiImageStyleSuffix
        self.aiVideoEnabled = aiVideoEnabled
    }
}

import Foundation

public struct KenBurnsParams: Codable, Equatable, Sendable {
    public var startScale: Double
    public var endScale: Double
    public var startX: Double
    public var startY: Double
    public var endX: Double
    public var endY: Double
    public var pulse: Bool

    public init(
        startScale: Double,
        endScale: Double,
        startX: Double,
        startY: Double,
        endX: Double,
        endY: Double,
        pulse: Bool
    ) {
        self.startScale = startScale
        self.endScale = endScale
        self.startX = startX
        self.startY = startY
        self.endX = endX
        self.endY = endY
        self.pulse = pulse
    }

    public static func forBeat(index: Int, enabled: Bool, pulse: Bool) -> KenBurnsParams {
        guard enabled else {
            return KenBurnsParams(startScale: 1, endScale: 1, startX: 0, startY: 0, endX: 0, endY: 0, pulse: false)
        }
        let even = index % 2 == 0
        return KenBurnsParams(
            startScale: even ? 1.0 : 1.12,
            endScale: even ? 1.14 : 1.0,
            startX: even ? -0.04 : 0.03,
            startY: even ? 0.02 : -0.03,
            endX: even ? 0.03 : -0.02,
            endY: even ? -0.02 : 0.03,
            pulse: pulse
        )
    }
}

public struct PlannedClip: Codable, Equatable, Sendable {
    public var beatID: String
    public var start: Double
    public var duration: Double
    public var transitionIn: TransitionType
    public var kenBurns: KenBurnsParams
    public var titleOverlay: String?
    public var stepNumber: Int?
    public var sourceKind: AssetKind
    public var sourcePath: String

    public init(
        beatID: String,
        start: Double,
        duration: Double,
        transitionIn: TransitionType,
        kenBurns: KenBurnsParams,
        titleOverlay: String?,
        stepNumber: Int?,
        sourceKind: AssetKind,
        sourcePath: String
    ) {
        self.beatID = beatID
        self.start = start
        self.duration = duration
        self.transitionIn = transitionIn
        self.kenBurns = kenBurns
        self.titleOverlay = titleOverlay
        self.stepNumber = stepNumber
        self.sourceKind = sourceKind
        self.sourcePath = sourcePath
    }

    public var end: Double { start + duration }
}

public struct PlannedAudio: Codable, Equatable, Sendable {
    public var path: String
    public var start: Double
    public var duration: Double
    public var volume: Double

    public init(path: String, start: Double, duration: Double, volume: Double) {
        self.path = path
        self.start = start
        self.duration = duration
        self.volume = volume
    }
}

public struct TimelinePlan: Codable, Equatable, Sendable {
    public var width: Int
    public var height: Int
    public var frameRate: Int
    public var duration: Double
    public var clips: [PlannedClip]
    public var captions: [CaptionCue]
    public var voice: PlannedAudio?
    public var music: PlannedAudio?
    public var grade: ColorGrade
    public var captionStyle: CaptionStyle
    public var transition: TransitionType
    public var overlap: Double

    public init(
        width: Int,
        height: Int,
        frameRate: Int,
        duration: Double,
        clips: [PlannedClip],
        captions: [CaptionCue],
        voice: PlannedAudio?,
        music: PlannedAudio?,
        grade: ColorGrade,
        captionStyle: CaptionStyle,
        transition: TransitionType,
        overlap: Double
    ) {
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.duration = duration
        self.clips = clips
        self.captions = captions
        self.voice = voice
        self.music = music
        self.grade = grade
        self.captionStyle = captionStyle
        self.transition = transition
        self.overlap = overlap
    }
}

public enum TimelinePlanner {
    public static func overlap(for transition: TransitionType) -> Double {
        switch transition {
        case .hardCut: return 0
        case .fade: return 0.22
        case .zoom: return 0.18
        case .whip: return 0.16
        }
    }

    public static func plan(
        storyboard: Storyboard,
        preset: Preset,
        aspect: AspectRatio,
        assetsByBeat: [String: AssetRef],
        captions: [CaptionCue],
        voicePath: String?,
        voiceDuration: Double?,
        musicPath: String?,
        musicVolume: Double
    ) -> TimelinePlan {
        let size = aspect.pixelSize
        let transition = preset.pace.transition
        let overlapAmount = overlap(for: transition)
        var clips: [PlannedClip] = []
        var cursor = 0.0

        for (index, beat) in storyboard.beats.enumerated() {
            let asset = assetsByBeat[beat.id]
            let incoming = index == 0 ? TransitionType.hardCut : transition
            if index > 0 {
                cursor -= overlapAmount
            }
            let clip = PlannedClip(
                beatID: beat.id,
                start: cursor,
                duration: beat.duration,
                transitionIn: incoming,
                kenBurns: KenBurnsParams.forBeat(
                    index: index,
                    enabled: preset.footage.kenBurns,
                    pulse: preset.footage.zoomPulse
                ),
                titleOverlay: (index == 0 || beat.role == .hook) ? beat.text : nil,
                stepNumber: beat.stepNumber,
                sourceKind: asset?.kind ?? .generatedCard,
                sourcePath: asset?.relativePath ?? ""
            )
            clips.append(clip)
            cursor += beat.duration
        }

        let duration = max(storyboard.duration, clips.last?.end ?? 0)
        return TimelinePlan(
            width: size.width,
            height: size.height,
            frameRate: 30,
            duration: duration,
            clips: clips,
            captions: captions,
            voice: voicePath.map { PlannedAudio(path: $0, start: 0, duration: voiceDuration ?? duration, volume: 1.0) },
            music: musicPath.map { PlannedAudio(path: $0, start: 0, duration: duration, volume: musicVolume) },
            grade: preset.colorGrade,
            captionStyle: preset.captionStyle,
            transition: transition,
            overlap: overlapAmount
        )
    }
}

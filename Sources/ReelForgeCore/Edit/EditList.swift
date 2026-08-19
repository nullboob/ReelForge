import Foundation

/// Shared edit decision list. Windows and Mac render the same JSON.
public struct EditAudio: Codable, Equatable, Sendable {
    public var path: String
    public var start: Double
    public var duration: Double

    public init(path: String, start: Double, duration: Double) {
        self.path = path
        self.start = start
        self.duration = duration
    }
}

public struct EditDuck: Codable, Equatable, Sendable {
    public var gapDb: Double
    public var speechDb: Double
    public var mode: String

    public init(gapDb: Double = -8, speechDb: Double = -18, mode: String = "sidechaincompress") {
        self.gapDb = gapDb
        self.speechDb = speechDb
        self.mode = mode
    }

    public static let standard = EditDuck()
}

public struct EditCaptions: Codable, Equatable, Sendable {
    public var assPath: String
    public var renderer: String
    public var styleID: String

    public init(assPath: String, renderer: String, styleID: String) {
        self.assPath = assPath
        self.renderer = renderer
        self.styleID = styleID
    }
}

public struct EditGrade: Codable, Equatable, Sendable {
    public var contrast: Double
    public var saturation: Double
    public var warmth: Double
    public var vignette: Double
    public var unsharp: Bool
    public var grain: Bool

    public init(contrast: Double, saturation: Double, warmth: Double, vignette: Double, unsharp: Bool = true, grain: Bool = false) {
        self.contrast = contrast
        self.saturation = saturation
        self.warmth = warmth
        self.vignette = vignette
        self.unsharp = unsharp
        self.grain = grain
    }

    public static func from(_ grade: ColorGrade, grain: Bool) -> EditGrade {
        EditGrade(
            contrast: grade.contrast,
            saturation: grade.saturation,
            warmth: grade.warmth,
            vignette: grade.vignette,
            unsharp: true,
            grain: grain
        )
    }
}

public struct EditHook: Codable, Equatable, Sendable {
    public var punchIn: Double
    public var holdSec: Double
    public var flashFrames: Int
    public var fadeFromBlack: Bool

    public init(punchIn: Double = 1.12, holdSec: Double = 1.5, flashFrames: Int = 0, fadeFromBlack: Bool = false) {
        self.punchIn = min(1.15, max(1.08, punchIn))
        self.holdSec = holdSec
        self.flashFrames = flashFrames
        self.fadeFromBlack = false
    }

    public static let standard = EditHook()

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        punchIn = min(1.15, max(1.08, try c.decodeIfPresent(Double.self, forKey: .punchIn) ?? 1.12))
        holdSec = try c.decodeIfPresent(Double.self, forKey: .holdSec) ?? 1.5
        flashFrames = try c.decodeIfPresent(Int.self, forKey: .flashFrames) ?? 0
        fadeFromBlack = false
    }
}

public struct EditClip: Codable, Equatable, Sendable {
    public var beatID: String
    public var role: String
    public var start: Double
    public var duration: Double
    public var source: String
    public var kind: String
    public var sourceID: String?
    public var kenBurns: Bool
    public var zoomPulse: Bool
    public var punchIn: Double?
    public var transitionIn: String

    public init(
        beatID: String,
        role: String,
        start: Double,
        duration: Double,
        source: String,
        kind: String,
        sourceID: String? = nil,
        kenBurns: Bool = false,
        zoomPulse: Bool = false,
        punchIn: Double? = nil,
        transitionIn: String = "hardCut"
    ) {
        self.beatID = beatID
        self.role = role
        self.start = start
        self.duration = duration
        self.source = source
        self.kind = kind
        self.sourceID = sourceID
        self.kenBurns = kenBurns
        self.zoomPulse = zoomPulse
        self.punchIn = punchIn
        self.transitionIn = role == "hook" ? "hardCut" : transitionIn
    }
}

public struct EditEncoder: Codable, Equatable, Sendable {
    public var preferred: [String]
    public var pixFmt: String
    public var faststart: Bool

    public init(
        preferred: [String] = EditEncoder.whitelist,
        pixFmt: String = "yuv420p",
        faststart: Bool = true
    ) {
        self.preferred = preferred
        self.pixFmt = pixFmt
        self.faststart = faststart
    }

    public static let whitelist = [
        "h264_nvenc", "h264_qsv", "h264_amf", "h264_videotoolbox", "libx264"
    ]
}

public struct EditList: Codable, Equatable, Sendable {
    public var version: Int
    public var width: Int
    public var height: Int
    public var fps: Int
    public var duration: Double
    public var audioMaster: Bool
    public var voice: EditAudio
    public var music: EditAudio
    public var duck: EditDuck
    public var captions: EditCaptions
    public var grade: EditGrade
    public var hook: EditHook
    public var clips: [EditClip]
    public var encoder: EditEncoder

    public init(
        version: Int = 1,
        width: Int,
        height: Int,
        fps: Int = 30,
        duration: Double,
        audioMaster: Bool = true,
        voice: EditAudio,
        music: EditAudio,
        duck: EditDuck = .standard,
        captions: EditCaptions,
        grade: EditGrade,
        hook: EditHook = .standard,
        clips: [EditClip],
        encoder: EditEncoder = EditEncoder()
    ) {
        self.version = version
        self.width = width
        self.height = height
        self.fps = fps
        self.duration = duration
        self.audioMaster = true
        self.voice = voice
        self.music = music
        self.duck = duck
        self.captions = captions
        self.grade = grade
        self.hook = hook
        self.clips = clips
        self.encoder = encoder
    }

    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public func write(to url: URL) throws {
        try jsonData().write(to: url, options: .atomic)
    }

    public static func load(from url: URL) throws -> EditList {
        try JSONDecoder().decode(EditList.self, from: Data(contentsOf: url))
    }

    /// One-encode graph: cover → cuts → punch/Ken Burns → eq/unsharp/vignette → ass= → sidechaincompress.
    public func filterComplex(fontsDir: String, burnCaptions: Bool) -> String {
        var parts: [String] = []
        var labels: [String] = []
        for (index, clip) in clips.enumerated() {
            let vf = videoFilter(for: clip, index: index)
            parts.append("[\(index):v]\(vf)[v\(index)]")
            labels.append("[v\(index)]")
        }
        if clips.isEmpty {
            parts.append("color=c=black:s=\(width)x\(height):d=\(max(0.4, duration)):r=\(fps)[vcat]")
        } else if clips.count == 1 {
            parts.append("\(labels[0])null[vcat]")
        } else {
            parts.append("\(labels.joined())concat=n=\(clips.count):v=1:a=0[vcat]")
        }
        parts.append("[vcat]\(gradeFilter())[vg]")
        if burnCaptions && !captions.assPath.isEmpty && captions.renderer != "off" {
            let ass = captions.assPath.replacingOccurrences(of: "\\", with: "/")
            let fonts = fontsDir.replacingOccurrences(of: "\\", with: "/")
            parts.append("[vg]ass=\(ass):fontsdir=\(fonts)[vout]")
        } else {
            parts.append("[vg]null[vout]")
        }
        let voiceIndex = clips.count
        let musicIndex = clips.count + 1
        let gap = pow(10.0, duck.gapDb / 20.0)
        parts.append("[\(voiceIndex):a]aformat=sample_fmts=fltp:channel_layouts=stereo[vo]")
        parts.append("[\(musicIndex):a]aformat=sample_fmts=fltp:channel_layouts=stereo,volume=\(String(format: "%.4f", gap))[bg]")
        parts.append("[bg][vo]sidechaincompress=threshold=0.02:ratio=8:attack=12:release=220:makeup=1[ducked]")
        parts.append("[vo][ducked]amix=inputs=2:duration=first:normalize=0[a]")
        return parts.joined(separator: ";")
    }

    public func videoFilter(for clip: EditClip, index: Int) -> String {
        let w = width - (width % 2)
        let h = height - (height % 2)
        let cover = "scale=\(w):\(h):force_original_aspect_ratio=increase:force_divisible_by=2,crop=\(w):\(h),setsar=1"
        var chain = [cover]
        let isHook = clip.role == "hook" || index == 0
        if isHook {
            let punch = clip.punchIn ?? hook.punchIn
            let frames = max(8, Int((hook.holdSec * Double(fps)).rounded()))
            let startZ = String(format: "%.3f", punch)
            let deltaZ = String(format: "%.3f", punch - 1)
            chain.append(
                "zoompan=z='if(lt(on,\(frames)),\(startZ)-\(deltaZ)*on/\(frames),1)':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=1:s=\(w)x\(h):fps=\(fps)"
            )
            if hook.flashFrames > 0 {
                chain.append("eq=brightness='if(lt(n,\(hook.flashFrames)),0.45,0)'")
            }
        } else if clip.kenBurns {
            let dur = max(0.4, clip.duration)
            chain.append("crop=\(w):\(h):'((in_w-out_w)*t/\(String(format: "%.3f", dur)))':'((in_h-out_h)*t/\(String(format: "%.3f", dur))*0.45)'")
        }
        chain.append("trim=duration=\(String(format: "%.3f", max(0.4, clip.duration)))")
        chain.append("setpts=PTS-STARTPTS")
        chain.append("fps=\(fps)")
        chain.append("format=yuv420p")
        return chain.joined(separator: ",")
    }

    public func gradeFilter() -> String {
        var parts = [
            "eq=contrast=\(String(format: "%.3f", grade.contrast)):saturation=\(String(format: "%.3f", grade.saturation)):brightness=\(String(format: "%.3f", grade.warmth * 0.02))"
        ]
        if grade.unsharp {
            parts.append("unsharp=5:5:0.6:5:5:0.0")
        }
        if grade.vignette > 0.05 {
            parts.append("vignette=PI/5")
        }
        if grade.grain {
            parts.append("noise=alls=8:allf=t")
        }
        return parts.joined(separator: ",")
    }

    public static func make(
        beats: [Beat],
        sources: [String: (path: String, kind: String, sourceID: String?)],
        voicePath: String,
        musicPath: String,
        duration: Double,
        width: Int,
        height: Int,
        grade: ColorGrade,
        grain: Bool,
        kenBurns: Bool,
        zoomPulse: Bool,
        assPath: String,
        captionStyleID: String,
        captionRenderer: String,
        fps: Int = 30
    ) -> EditList {
        let clips = beats.enumerated().map { index, beat -> EditClip in
            let source = sources[beat.id]
            let role = beat.role.edlName
            let isHook = role == "hook" || index == 0
            let kind = source?.kind ?? "card"
            return EditClip(
                beatID: beat.id,
                role: role,
                start: beat.start,
                duration: beat.duration,
                source: source?.path ?? "",
                kind: kind,
                sourceID: source?.sourceID,
                kenBurns: kenBurns && (kind == "image" || kind == "card"),
                zoomPulse: zoomPulse,
                punchIn: isHook ? 1.12 : nil,
                transitionIn: isHook ? "hardCut" : "hardCut"
            )
        }
        return EditList(
            width: width,
            height: height,
            fps: fps,
            duration: duration,
            voice: EditAudio(path: voicePath, start: 0, duration: duration),
            music: EditAudio(path: musicPath, start: 0, duration: duration),
            captions: EditCaptions(assPath: assPath, renderer: captionRenderer, styleID: captionStyleID),
            grade: EditGrade.from(grade, grain: grain),
            hook: EditHook(punchIn: 1.12, holdSec: 1.5, flashFrames: zoomPulse ? 8 : 0),
            clips: clips
        )
    }
}

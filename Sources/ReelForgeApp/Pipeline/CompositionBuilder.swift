import AVFoundation
import Foundation

struct BuiltComposition {
    var composition: AVMutableComposition
    var videoComposition: AVMutableVideoComposition
    var audioMix: AVMutableAudioMix
    var duration: CMTime
}

enum CompositionBuilder {
    static func build(plan: TimelinePlan, workDir: URL) async throws -> BuiltComposition {
        let composition = AVMutableComposition()
        guard let videoA = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let videoB = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw ExportError.compositionFailed }

        var instructions: [AVMutableVideoCompositionInstruction] = []
        let renderSize = CGSize(width: plan.width, height: plan.height)
        let timescale: CMTimeScale = 600

        for (index, clip) in plan.clips.enumerated() {
            let url = workDir.appendingPathComponent(clip.sourcePath)
            let asset = AVURLAsset(url: url)
            guard let srcTrack = asset.tracks(withMediaType: .video).first else { continue }
            let dest = index % 2 == 0 ? videoA : videoB
            let start = CMTime(seconds: clip.start, preferredTimescale: timescale)
            let duration = CMTime(seconds: clip.duration, preferredTimescale: timescale)
            let srcDuration = asset.duration
            let usable = CMTimeMinimum(duration, srcDuration)
            try dest.insertTimeRange(CMTimeRange(start: .zero, duration: usable), of: srcTrack, at: start)
            if usable < duration {
                var cursor = start + usable
                var remaining = duration - usable
                while remaining.seconds > 0.05 {
                    let slice = CMTimeMinimum(remaining, srcDuration)
                    try dest.insertTimeRange(CMTimeRange(start: .zero, duration: slice), of: srcTrack, at: cursor)
                    cursor = cursor + slice
                    remaining = remaining - slice
                }
            }
        }

        // Layer instructions over the union of clip ranges.
        let events = plan.clips.flatMap { [$0.start, $0.end] }.sorted()
        var unique: [Double] = []
        for t in events {
            if unique.last.map({ abs($0 - t) > 0.0005 }) ?? true {
                unique.append(t)
            }
        }
        if unique.count < 2, let first = plan.clips.first {
            unique = [first.start, first.end]
        }

        for i in 0..<max(0, unique.count - 1) {
            let a = unique[i]
            let b = unique[i + 1]
            if b - a < 0.001 { continue }
            let range = CMTimeRange(
                start: CMTime(seconds: a, preferredTimescale: timescale),
                duration: CMTime(seconds: b - a, preferredTimescale: timescale)
            )
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = range
            var layers: [AVMutableVideoCompositionLayerInstruction] = []

            let active = plan.clips.enumerated().filter { $0.element.start < b - 0.0001 && $0.element.end > a + 0.0001 }
            for (index, clip) in active {
                let track = index % 2 == 0 ? videoA : videoB
                let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
                let mid = (a + b) / 2
                applyTransition(layer: layer, clip: clip, plan: plan, time: mid, range: range, renderSize: renderSize)
                layers.append(layer)
            }
            instruction.layerInstructions = layers
            instructions.append(instruction)
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.instructions = instructions
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.renderSize = renderSize
        videoComposition.renderScale = 1

        let audioMix = AVMutableAudioMix()
        var params: [AVMutableAudioMixInputParameters] = []

        if let voice = plan.voice {
            let voiceURL = resolve(path: voice.path, workDir: workDir)
            if let voiceParams = try insertAudio(
                composition: composition,
                path: voiceURL,
                start: voice.start,
                duration: plan.duration,
                volume: voice.volume,
                timescale: timescale
            ) {
                params.append(voiceParams)
            }
        }

        if let music = plan.music {
            let resolved = resolve(path: music.path, workDir: workDir)
            if let musicParams = try? insertLoopedAudio(
                composition: composition,
                path: resolved,
                duration: plan.duration,
                volume: music.volume,
                timescale: timescale
            ) {
                params.append(musicParams)
            }
        }

        audioMix.inputParameters = params
        let duration = CMTime(seconds: plan.duration, preferredTimescale: timescale)
        return BuiltComposition(
            composition: composition,
            videoComposition: videoComposition,
            audioMix: audioMix,
            duration: duration
        )
    }

    private static func resolve(path: String, workDir: URL) -> URL {
        let asIs = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: asIs.path) { return asIs }
        return workDir.appendingPathComponent((path as NSString).lastPathComponent)
    }

    private static func applyTransition(
        layer: AVMutableVideoCompositionLayerInstruction,
        clip: PlannedClip,
        plan: TimelinePlan,
        time: Double,
        range: CMTimeRange,
        renderSize: CGSize
    ) {
        let overlap = plan.overlap
        if overlap > 0, clip.transitionIn != .hardCut, time < clip.start + overlap {
            let p = max(0, min(1, (time - clip.start) / overlap))
            switch clip.transitionIn {
            case .fade:
                layer.setOpacityRamp(fromStartOpacity: 0, toEndOpacity: 1, timeRange: range)
            case .zoom:
                let from = makeTransform(scale: 1.12, tx: 0, ty: 0, size: renderSize)
                let to = makeTransform(scale: 1.0, tx: 0, ty: 0, size: renderSize)
                layer.setTransformRamp(fromStart: from, toEnd: to, timeRange: range)
            case .whip:
                let from = makeTransform(scale: 1, tx: renderSize.width * (1 - p), ty: 0, size: renderSize)
                let to = makeTransform(scale: 1, tx: 0, ty: 0, size: renderSize)
                layer.setTransformRamp(fromStart: from, toEnd: to, timeRange: range)
            case .hardCut:
                break
            }
        } else if overlap > 0, time > clip.end - overlap {
            switch plan.transition {
            case .fade:
                layer.setOpacityRamp(fromStartOpacity: 1, toEndOpacity: 0, timeRange: range)
            case .zoom:
                let from = makeTransform(scale: 1.0, tx: 0, ty: 0, size: renderSize)
                let to = makeTransform(scale: 1.1, tx: 0, ty: 0, size: renderSize)
                layer.setTransformRamp(fromStart: from, toEnd: to, timeRange: range)
            case .whip:
                let from = makeTransform(scale: 1, tx: 0, ty: 0, size: renderSize)
                let to = makeTransform(scale: 1, tx: -renderSize.width, ty: 0, size: renderSize)
                layer.setTransformRamp(fromStart: from, toEnd: to, timeRange: range)
            case .hardCut:
                break
            }
        }
    }

    private static func makeTransform(scale: CGFloat, tx: CGFloat, ty: CGFloat, size: CGSize) -> CGAffineTransform {
        var t = CGAffineTransform.identity
        t = t.translatedBy(x: size.width / 2 + tx, y: size.height / 2 + ty)
        t = t.scaledBy(x: scale, y: scale)
        t = t.translatedBy(x: -size.width / 2, y: -size.height / 2)
        return t
    }

    private static func insertAudio(
        composition: AVMutableComposition,
        path: URL,
        start: Double,
        duration: Double,
        volume: Double,
        timescale: CMTimeScale
    ) throws -> AVMutableAudioMixInputParameters? {
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        let asset = AVURLAsset(url: path)
        guard let src = asset.tracks(withMediaType: .audio).first,
              let dest = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { return nil }
        let insert = CMTimeMinimum(asset.duration, CMTime(seconds: duration, preferredTimescale: timescale))
        try dest.insertTimeRange(
            CMTimeRange(start: .zero, duration: insert),
            of: src,
            at: CMTime(seconds: start, preferredTimescale: timescale)
        )
        let params = AVMutableAudioMixInputParameters(track: dest)
        params.setVolume(Float(volume), at: .zero)
        return params
    }

    private static func insertLoopedAudio(
        composition: AVMutableComposition,
        path: URL,
        duration: Double,
        volume: Double,
        timescale: CMTimeScale
    ) throws -> AVMutableAudioMixInputParameters? {
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        let asset = AVURLAsset(url: path)
        guard let src = asset.tracks(withMediaType: .audio).first,
              let dest = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { return nil }
        var cursor = CMTime.zero
        let total = CMTime(seconds: duration, preferredTimescale: timescale)
        while cursor < total {
            let remaining = total - cursor
            let slice = CMTimeMinimum(asset.duration, remaining)
            try dest.insertTimeRange(CMTimeRange(start: .zero, duration: slice), of: src, at: cursor)
            cursor = cursor + slice
        }
        let params = AVMutableAudioMixInputParameters(track: dest)
        params.setVolume(Float(volume), at: .zero)
        return params
    }
}

enum ExportError: LocalizedError {
    case compositionFailed
    case exportFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .compositionFailed: return "Could not build the timeline composition."
        case .exportFailed(let message): return message
        case .cancelled: return "Export was cancelled."
        }
    }
}

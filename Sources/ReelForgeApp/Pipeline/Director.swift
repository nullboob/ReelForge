import AppKit
import Foundation

struct GenerateRequest: Sendable {
    var topic: String
    var preset: Preset
    var aspect: AspectRatio
    var duration: Int
    var voiceIdentifier: String?
    var voiceoverURL: URL?
    var footageURLs: [URL]
    var useUnsplash: Bool
    var useLocalAI: Bool
    var unsplashKey: String?
    var project: Project
}

struct GenerateResult: Sendable {
    var project: Project
    var exportURL: URL
    var timeline: TimelinePlan
}

final class Director: @unchecked Sendable {
    private let scriptService = ScriptService()
    private let speechService = SpeechService()
    private let captionService = CaptionService()
    private let footageService = FootageService()

    func run(
        _ request: GenerateRequest,
        progress: @escaping @MainActor (PipelineProgress) -> Void
    ) async throws -> GenerateResult {
        var project = request.project
        project.updatedAt = Date()
        project.presetID = request.preset.id
        project.topic = request.topic
        project.warnings = []
        let workDir = try ProjectStore.prepare(project)
        let assetsDir = ProjectStore.assetsDirectory(for: project.id)
        var completed: [PipelineStep] = []

        func emit(_ step: PipelineStep, _ detail: String, extra: Double = 0) async {
            let base = Double(completed.count) / Double(PipelineStep.allCases.count)
            let snapshot = PipelineProgress(
                current: step,
                completed: completed,
                detail: detail,
                fraction: min(0.98, base + extra)
            )
            await progress(snapshot)
        }

        try Task.checkCancellation()
        await emit(.script, PipelineStep.script.defaultDetail)
        let (script, scriptWarnings) = await scriptService.write(
            topic: request.topic,
            preset: request.preset,
            preferOllama: request.useLocalAI
        )
        project.script = script
        project.warnings.append(contentsOf: scriptWarnings)
        completed.append(.script)
        try ProjectStore.save(project)

        try Task.checkCancellation()
        await emit(.storyboard, "Timing beats to \(request.preset.pace.cutMinSec)–\(request.preset.pace.cutMaxSec)s cuts")
        var storyboard = StoryboardBuilder.build(
            script: script,
            preset: request.preset,
            duration: Double(request.duration)
        )
        project.storyboard = storyboard
        completed.append(.storyboard)
        try ProjectStore.save(project)

        try Task.checkCancellation()
        await emit(.voice, request.voiceoverURL == nil ? "Generating speech with the system voice" : "Using your dropped voiceover")
        let voiceURL = assetsDir.appendingPathComponent("voice.wav")
        var voiceDuration: Double
        if let provided = request.voiceoverURL {
            let accessed = provided.startAccessingSecurityScopedResource()
            defer { if accessed { provided.stopAccessingSecurityScopedResource() } }
            if FileManager.default.fileExists(atPath: voiceURL.path) {
                try? FileManager.default.removeItem(at: voiceURL)
            }
            do {
                try FileManager.default.copyItem(at: provided, to: voiceURL)
                voiceDuration = await speechService.durationOfAudio(at: voiceURL) ?? speechService.estimateDuration(text: script.fullText)
            } catch {
                voiceDuration = try await speechService.synthesize(
                    text: script.fullText,
                    voiceIdentifier: request.voiceIdentifier,
                    to: voiceURL
                )
                project.warnings.append("Could not copy the dropped voiceover — synthesized speech instead.")
            }
        } else {
            do {
                voiceDuration = try await speechService.synthesize(
                    text: script.fullText,
                    voiceIdentifier: request.voiceIdentifier,
                    to: voiceURL
                )
            } catch {
                voiceDuration = speechService.estimateDuration(text: script.fullText)
                try MusicBedSynthesizer.writeSilence(duration: voiceDuration, to: voiceURL)
                project.warnings.append("Speech synthesis failed — music still plays and export continues.")
            }
        }
        project.assets.removeAll { $0.kind == .voiceover }
        project.assets.append(AssetRef(id: "voice", kind: .voiceover, relativePath: "voice.wav"))
        if abs(voiceDuration - storyboard.duration) > 0.8 {
            storyboard = StoryboardBuilder.rescale(storyboard, to: voiceDuration)
            project.storyboard = storyboard
        }
        completed.append(.voice)
        try ProjectStore.save(project)

        try Task.checkCancellation()
        await emit(.captions, "Burning captions")
        let captionResult = await captionService.cues(
            script: script,
            storyboard: storyboard,
            preset: request.preset,
            voiceURL: voiceURL,
            allowLocalWhisper: request.useLocalAI
        )
        project.captions = captionResult.cues
        if let warning = captionResult.warning { project.warnings.append(warning) }
        completed.append(.captions)
        try ProjectStore.save(project)

        try Task.checkCancellation()
        await emit(.footage, "Collecting B-roll and styled cards")
        let footage = await footageService.gather(
            beats: storyboard.beats,
            preset: request.preset,
            aspect: request.aspect,
            workDir: assetsDir,
            localFiles: request.footageURLs,
            unsplashKey: request.unsplashKey,
            useUnsplash: request.useUnsplash,
            useLocalAI: request.useLocalAI
        ) { detail in
            Task { await emit(.footage, detail, extra: 0.05) }
        }
        project.attributions = footage.attributions
        project.warnings.append(contentsOf: footage.warnings)
        project.assets.removeAll { $0.kind == .image || $0.kind == .video || $0.kind == .generatedCard }
        project.assets.append(contentsOf: footage.assignments.values.map(\.asset))
        completed.append(.footage)
        try ProjectStore.save(project)

        try Task.checkCancellation()
        await emit(.music, "Writing a \(request.preset.music.mood.rawValue) bed at \(request.preset.music.bpm) BPM")
        let musicURL = assetsDir.appendingPathComponent("music.wav")
        try MusicBedSynthesizer.writeLoop(mood: request.preset.music.mood, bpm: request.preset.music.bpm, to: musicURL)
        project.assets.removeAll { $0.kind == .music }
        project.assets.append(AssetRef(id: "music", kind: .music, relativePath: "music.wav"))
        completed.append(.music)
        try ProjectStore.save(project)

        try Task.checkCancellation()
        await emit(.compose, "Rendering Ken Burns clips, grade, and transitions")
        let assetsByBeat = Dictionary(uniqueKeysWithValues: footage.assignments.map { ($0.key, $0.value.asset) })
        var plan = TimelinePlanner.plan(
            storyboard: storyboard,
            preset: request.preset,
            aspect: request.aspect,
            assetsByBeat: assetsByBeat,
            captions: project.captions,
            voicePath: voiceURL.path,
            voiceDuration: voiceDuration,
            musicPath: musicURL.path,
            musicVolume: 0.34 * request.preset.music.duckLinear
        )

        var renderedClips: [URL] = []
        let canvas = CGSize(width: plan.width, height: plan.height)
        for (index, clip) in plan.clips.enumerated() {
            try Task.checkCancellation()
            await emit(.compose, "Composing beat \(index + 1)/\(plan.clips.count)", extra: 0.08)
            let out = assetsDir.appendingPathComponent("clip-\(index).mp4")
            let assignment = footage.assignments[clip.beatID]
            let beat = storyboard.beats.first { $0.id == clip.beatID }
            let beatCaptions = project.captions.map { cue in
                CaptionCue(
                    id: cue.id,
                    text: cue.text,
                    start: cue.start,
                    duration: cue.duration,
                    words: cue.words,
                    highlightWordIndex: cue.highlightWordIndex
                )
            }
            if assignment?.asset.kind == .video, let file = assignment?.fileURL {
                try await ClipWriter.writeVideo(
                    source: file,
                    duration: clip.duration,
                    size: canvas,
                    grade: request.preset.colorGrade,
                    grain: request.preset.footage.overlayGrain,
                    captions: beatCaptions,
                    captionStyle: request.preset.captionStyle,
                    title: clip.titleOverlay,
                    titleStyle: request.preset.titleCard,
                    stepNumber: clip.stepNumber,
                    timelineOffset: clip.start,
                    outputURL: out
                )
            } else {
                let fallbackBeat = beat ?? Beat(
                    id: clip.beatID,
                    index: index,
                    role: .body(index),
                    text: script.hook,
                    start: clip.start,
                    duration: clip.duration,
                    unsplashQuery: ""
                )
                let fallbackCard = CardRenderer.render(beat: fallbackBeat, preset: request.preset, size: canvas)
                    ?? NSImageFallback.black(size: canvas)
                let cgImage = assignment?.fileURL.flatMap { ImageIO.loadCGImage(from: $0) }
                    ?? ImageIO.cgImage(from: fallbackCard)
                guard let cgImage else { throw ExportError.compositionFailed }
                try await ClipWriter.writeStill(
                    image: cgImage,
                    duration: clip.duration,
                    size: canvas,
                    kenBurns: clip.kenBurns,
                    grade: request.preset.colorGrade,
                    grain: request.preset.footage.overlayGrain,
                    captions: beatCaptions,
                    captionStyle: request.preset.captionStyle,
                    title: clip.titleOverlay,
                    titleStyle: request.preset.titleCard,
                    stepNumber: clip.stepNumber,
                    timelineOffset: clip.start,
                    outputURL: out
                )
            }
            plan.clips[index].sourcePath = out.lastPathComponent
            plan.clips[index].sourceKind = .video
            renderedClips.append(out)
        }
        completed.append(.compose)

        try Task.checkCancellation()
        await emit(.export, "Writing H.264 MP4 to Movies/ReelForge")
        let built = try await CompositionBuilder.build(plan: plan, workDir: assetsDir)
        let exportURL = try ProjectStore.exportURL(presetID: request.preset.id, topic: request.topic)
        try await VideoExporter.export(
            built: built,
            to: exportURL,
            fallbackClips: renderedClips,
            fallbackAudio: [voiceURL, musicURL]
        )
        project.exportPath = exportURL.path
        project.updatedAt = Date()
        completed.append(.export)
        try ProjectStore.save(project)

        await progress(PipelineProgress(
            current: nil,
            completed: completed,
            detail: "Exported \(exportURL.lastPathComponent)",
            fraction: 1,
            isFinished: true
        ))

        return GenerateResult(project: project, exportURL: exportURL, timeline: plan)
    }
}

private enum NSImageFallback {
    static func black(size: CGSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.black.setFill()
        NSBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
        image.unlockFocus()
        return image
    }
}

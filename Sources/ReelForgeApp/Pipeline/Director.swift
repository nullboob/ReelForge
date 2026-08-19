import AppKit
import Foundation

struct GenerateRequest: Sendable {
    var topic: String
    var preset: Preset
    var aspect: AspectRatio
    var duration: Int
    var voiceIdentifier: String?
    var voiceSpeed: Double
    var beatPause: Double
    var voiceoverURL: URL?
    var footageURLs: [URL]
    var useUnsplash: Bool
    var usePexels: Bool
    var usePixabay: Bool
    var useLocalAI: Bool
    var localMode: String
    var comfyUrl: String
    var burnCaptions: Bool
    var exportSRT: Bool
    var unsplashKey: String?
    var pexelsKey: String?
    var pixabayKey: String?
    var captionStyleID: String
    var allowCards: Bool
    var channelType: ChannelType
    var target: VideoTarget
    var seriesName: String?
    var channel: ChannelKit
    var project: Project
}

struct DraftResult: Sendable {
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

    /// Script + storyboard + caption draft. Stops for human Accept.
    func draft(
        _ request: GenerateRequest,
        progress: @escaping @MainActor (PipelineProgress) -> Void
    ) async throws -> DraftResult {
        var project = request.project
        project.updatedAt = Date()
        project.presetID = request.preset.id
        project.topic = request.topic
        project.scriptAccepted = false
        project.warnings = []
        project.voiceIdentifier = request.voiceIdentifier
        project.captionStyleID = request.captionStyleID
        project.allowCards = request.allowCards
        _ = try ProjectStore.prepare(project)
        var completed: [PipelineStep] = []

        func emit(_ step: PipelineStep, _ detail: String) async {
            let base = Double(completed.count) / Double(PipelineStep.allCases.count)
            await progress(PipelineProgress(current: step, completed: completed, detail: detail, fraction: min(0.35, base)))
        }

        try Task.checkCancellation()
        await emit(.script, PipelineStep.script.defaultDetail)
        var (script, scriptWarnings) = await scriptService.write(
            topic: request.topic,
            preset: request.preset,
            preferOllama: request.useLocalAI,
            durationSec: request.duration,
            channelType: request.channelType
        )
        if HookRules.isForbiddenOpen(script.hook) {
            let fallback = ScriptWriter.write(
                topic: request.topic,
                presetID: request.preset.id,
                durationSec: request.duration,
                channelType: request.channelType
            )
            script.hook = fallback.hook
            project.warnings.append("Replaced a greeting / lecture open with a hook claim.")
        }
        project.script = script
        project.warnings.append(contentsOf: scriptWarnings)
        completed.append(.script)
        try ProjectStore.save(project)

        try Task.checkCancellation()
        await emit(.storyboard, "Timing beats to \(request.preset.pace.cutMinSec)–\(request.preset.pace.cutMaxSec)s cuts")
        var storyboard = try StoryboardBuilder.build(
            script: script,
            preset: request.preset,
            duration: Double(request.duration)
        )
        storyboard = StoryboardBuilder.appendingOutro(
            storyboard,
            channelName: request.channel.name,
            enabled: request.channel.outroEnabled
        )
        guard let first = storyboard.beats.first, case .hook = first.role else {
            throw StoryboardError.missingHook
        }
        project.storyboard = storyboard
        completed.append(.storyboard)
        try ProjectStore.save(project)

        await emit(.review, "Draft captions for the script desk")
        let captionResult = await captionService.cues(
            script: script,
            storyboard: storyboard,
            preset: request.preset,
            voiceURL: nil,
            allowLocalWhisper: false,
            captionStyleID: request.captionStyleID
        )
        project.captions = captionResult.cues
        completed.append(.review)
        try ProjectStore.save(project)

        await progress(PipelineProgress(
            current: .review,
            completed: completed,
            detail: "Accept the script to render. Nothing exports until you click Accept.",
            fraction: 0.28
        ))
        return DraftResult(project: project)
    }

    /// Voice, stock, music, compose, publish pack. Requires an accepted script.
    func compose(
        _ request: GenerateRequest,
        progress: @escaping @MainActor (PipelineProgress) -> Void
    ) async throws -> GenerateResult {
        var project = request.project
        guard project.scriptAccepted, let script = project.script, var storyboard = project.storyboard else {
            throw ExportError.exportFailed("Accept the script before compose.")
        }
        guard let first = storyboard.beats.first, case .hook = first.role else {
            throw StoryboardError.missingHook
        }

        let workDir = try ProjectStore.prepare(project)
        let assetsDir = ProjectStore.assetsDirectory(for: project.id)
        var completed: [PipelineStep] = [.script, .storyboard, .review]

        func emit(_ step: PipelineStep, _ detail: String, extra: Double = 0) async {
            let base = Double(completed.count) / Double(PipelineStep.allCases.count)
            await progress(PipelineProgress(current: step, completed: completed, detail: detail, fraction: min(0.98, base + extra)))
        }

        try Task.checkCancellation()
        await emit(.voice, request.voiceoverURL == nil ? "Kokoro-class VO (never AVSpeech)" : "Using your dropped voiceover")
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
                project.ttsEngine = "Dropped VO"
            } catch {
                let spoken = try await speechService.synthesize(
                    text: spokenText(script, pause: request.beatPause),
                    voiceIdentifier: request.voiceIdentifier,
                    speed: request.voiceSpeed,
                    to: voiceURL
                )
                voiceDuration = spoken.duration
                project.ttsEngine = spoken.engine
                project.warnings.append("Could not copy the dropped voiceover — synthesized speech instead.")
            }
        } else {
            do {
                let spoken = try await speechService.synthesize(
                    text: spokenText(script, pause: request.beatPause),
                    voiceIdentifier: request.voiceIdentifier,
                    speed: request.voiceSpeed,
                    to: voiceURL
                )
                voiceDuration = spoken.duration
                project.ttsEngine = spoken.engine
            } catch {
                voiceDuration = speechService.estimateDuration(text: script.fullText)
                try MusicBedSynthesizer.writeSilence(duration: voiceDuration, to: voiceURL)
                project.warnings.append("No Kokoro and no edge-tts CLI — export continues without a spoken VO. AVSpeech is not used.")
            }
        }
        project.assets.removeAll { $0.kind == .voiceover }
        project.assets.append(AssetRef(id: "voice", kind: .voiceover, relativePath: "voice.wav"))
        if abs(voiceDuration - storyboard.duration) > 0.8 {
            storyboard = StoryboardBuilder.rescale(storyboard, to: voiceDuration)
            guard case .hook = storyboard.beats.first?.role else { throw StoryboardError.missingHook }
            project.storyboard = storyboard
        }
        completed.append(.voice)
        try ProjectStore.save(project)

        try Task.checkCancellation()
        await emit(.captions, "Keeping accepted script text; aligning word times")
        let captionResult = await captionService.cues(
            script: script,
            storyboard: storyboard,
            preset: request.preset,
            voiceURL: voiceURL,
            allowLocalWhisper: request.useLocalAI,
            captionStyleID: request.captionStyleID,
            existing: project.captions
        )
        project.captions = captionResult.cues
        if let warning = captionResult.warning { project.warnings.append(warning) }
        completed.append(.captions)
        try ProjectStore.save(project)

        try Task.checkCancellation()
        await emit(.footage, "User files, stock, then ComfyUI if up")
        let footage = await footageService.gather(
            beats: storyboard.beats,
            preset: request.preset,
            aspect: request.aspect,
            workDir: assetsDir,
            localFiles: request.footageURLs,
            unsplashKey: request.unsplashKey,
            pexelsKey: request.pexelsKey,
            pixabayKey: request.pixabayKey,
            useUnsplash: request.useUnsplash,
            usePexels: request.usePexels,
            usePixabay: request.usePixabay,
            useLocalAI: request.useLocalAI,
            localMode: request.localMode,
            comfyUrl: request.comfyUrl,
            channelName: request.channel.name
        ) { detail in
            Task { await emit(.footage, detail, extra: 0.05) }
        }
        project.attributions = footage.attributions
        project.warnings.append(contentsOf: footage.warnings)
        project.cardsOnly = footage.cardsOnly
        if footage.cardsOnly && !request.allowCards {
            throw ExportError.cardsOnly
        }
        project.assets.removeAll { $0.kind == .image || $0.kind == .video || $0.kind == .generatedCard }
        project.assets.append(contentsOf: footage.assignments.values.map(\.asset))
        completed.append(.footage)
        try ProjectStore.save(project)

        try Task.checkCancellation()
        await emit(.music, "Original-safe bed, sidechain-ducked −18 dB under VO")
        let musicURL = assetsDir.appendingPathComponent("music.wav")
        let musicSource = try await resolveMusic(channel: request.channel, preset: request.preset, to: musicURL, useLocalAI: request.useLocalAI)
        project.assets.removeAll { $0.kind == .music }
        project.assets.append(AssetRef(id: "music", kind: .music, relativePath: "music.wav"))
        completed.append(.music)

        var ledger = footage.attributions.enumerated().map { index, attr in
            LicenseEntry(
                id: "visual-\(index)",
                kind: "visual",
                source: attr.source,
                license: attr.source == "pexels" ? "Pexels License" : "Unsplash License (manual still)",
                clipID: attr.clipID,
                credit: "\(attr.photographer) / \(attr.source)",
                beatID: attr.beatID
            )
        }
        for (beatID, assignment) in footage.assignments where assignment.asset.kind == .generatedCard {
            ledger.append(LicenseEntry(
                id: assignment.asset.id,
                kind: "visual",
                source: "reelforge-card",
                license: "Generated in-app",
                credit: "Styled card",
                beatID: beatID
            ))
        }
        for (beatID, assignment) in footage.assignments where assignment.asset.kind == .video && assignment.asset.id.hasPrefix("local") {
            ledger.append(LicenseEntry(
                id: assignment.asset.id,
                kind: "visual",
                source: "user-local",
                license: "User provided",
                credit: "Local file",
                beatID: beatID
            ))
        }
        for (beatID, assignment) in footage.assignments {
            guard let credit = assignment.credit else { continue }
            ledger.append(LicenseEntry(
                id: assignment.asset.id,
                kind: "visual",
                source: assignment.asset.id,
                license: "Generated in-app",
                credit: credit,
                beatID: beatID
            ))
        }
        ledger.append(LicenseEntry(
            id: "music",
            kind: "audio",
            source: musicSource,
            license: musicSource == "user-folder" ? "User imported" : (musicSource == "ace-step" ? "Generated in-app" : "Original-safe bundled bed"),
            credit: musicSource == "user-folder" ? "Imported music folder" : (musicSource == "ace-step" ? "ACE-Step local" : "ReelForge \(request.preset.music.mood.rawValue) bed")
        ))
        ledger.append(LicenseEntry(
            id: "voice",
            kind: "audio",
            source: project.ttsEngine ?? "silence",
            license: "Generated voiceover",
            credit: project.ttsEngine ?? "silence"
        ))
        project.licenseLedger = ledger
        try ProjectStore.save(project)

        try Task.checkCancellation()
        await emit(.compose, "One-encode: cover, punch-in, grade, ass=, sidechaincompress")
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
            musicVolume: request.preset.music.duckLinear
        )
        // Same .ass Windows burns with ffmpeg ass= — karaoke parity, never subtitles=.
        let assLook = CaptionCatalog.look(id: request.captionStyleID)
        let assURL = assetsDir.appendingPathComponent("captions.ass")
        let assText = CaptionASS.build(cues: project.captions, look: assLook, width: plan.width, height: plan.height)
        try assText.write(to: assURL, atomically: true, encoding: .utf8)
        // VO starts at 0 with the hook. No music-only or logo open.

        var sources: [String: (path: String, kind: String, sourceID: String?)] = [:]
        for (beatID, assignment) in footage.assignments {
            let kind: String
            switch assignment.asset.kind {
            case .video: kind = "video"
            case .image: kind = "image"
            case .generatedCard: kind = "card"
            default: kind = "card"
            }
            sources[beatID] = (assignment.fileURL.path, kind, assignment.asset.id)
        }
        let document = EditList.make(
            beats: storyboard.beats,
            sources: sources,
            voicePath: voiceURL.path,
            musicPath: musicURL.path,
            duration: voiceDuration,
            width: plan.width,
            height: plan.height,
            grade: request.preset.colorGrade,
            grain: request.preset.footage.overlayGrain,
            kenBurns: request.preset.footage.kenBurns,
            zoomPulse: request.preset.footage.zoomPulse,
            assPath: assURL.path,
            captionStyleID: assLook.id,
            captionRenderer: assLook.renderer
        )
        try document.write(to: assetsDir.appendingPathComponent("edl.json"))

        var oneEncodeURL: URL?
        if FFmpegFallback.isAvailable {
            let dest = assetsDir.appendingPathComponent("one-encode.mp4")
            do {
                try EDLExporter.export(
                    document,
                    to: dest,
                    workDir: assetsDir,
                    fontsDir: CaptionCatalog.fontsDirectory()?.path ?? "",
                    burnCaptions: request.burnCaptions && !project.captions.isEmpty
                )
                oneEncodeURL = dest
            } catch {
                project.warnings.append("One-encode missed — per-clip fallback still uses sidechain duck.")
            }
        }

        var renderedClips: [URL] = []
        let canvas = CGSize(width: plan.width, height: plan.height)
        let logo = ChannelStore.logoURL(for: request.channel).flatMap { ImageIO.loadCGImage(from: $0) }
        if oneEncodeURL == nil {
        for (index, clip) in plan.clips.enumerated() {
            try Task.checkCancellation()
            await emit(.compose, "Composing beat \(index + 1)/\(plan.clips.count)", extra: 0.08)
            let out = assetsDir.appendingPathComponent("clip-\(index).mp4")
            let assignment = footage.assignments[clip.beatID]
            let beat = storyboard.beats.first { $0.id == clip.beatID }
            let beatCaptions = request.burnCaptions ? project.captions : []
            let clipLogo = clip.start < 1.5 ? nil : logo
            let look = CaptionCatalog.look(id: request.captionStyleID)
            let captionStyle = look.asCaptionStyle()
            if assignment?.asset.kind == .video, let file = assignment?.fileURL {
                try await ClipWriter.writeVideo(
                    source: file,
                    duration: clip.duration,
                    size: canvas,
                    grade: request.preset.colorGrade,
                    grain: request.preset.footage.overlayGrain,
                    zoomPulse: request.preset.footage.zoomPulse,
                    captions: beatCaptions,
                    captionStyle: captionStyle,
                    captionLook: look,
                    primaryHex: request.channel.primaryHex,
                    title: clip.titleOverlay,
                    titleStyle: request.preset.titleCard,
                    stepNumber: clip.stepNumber,
                    timelineOffset: clip.start,
                    logo: clipLogo,
                    outputURL: out
                )
            } else {
                let fallbackBeat = beat ?? Beat(
                    id: clip.beatID,
                    index: index,
                    role: .hook,
                    text: script.hook,
                    start: clip.start,
                    duration: clip.duration,
                    unsplashQuery: ""
                )
                let fallbackCard = CardRenderer.render(
                    beat: fallbackBeat,
                    preset: request.preset,
                    size: canvas,
                    channelName: request.channel.name
                ) ?? NSImageFallback.black(size: canvas)
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
                    captionStyle: captionStyle,
                    captionLook: look,
                    primaryHex: request.channel.primaryHex,
                    title: clip.titleOverlay,
                    titleStyle: request.preset.titleCard,
                    stepNumber: clip.stepNumber,
                    timelineOffset: clip.start,
                    logo: clipLogo,
                    outputURL: out
                )
            }
            plan.clips[index].sourcePath = out.lastPathComponent
            plan.clips[index].sourceKind = .video
            renderedClips.append(out)
        }
        }
        completed.append(.compose)

        try Task.checkCancellation()
        await emit(.package, "Building the YouTube publish pack")
        let credits = ledger.map(\.credit)
        var pack = PublishPackWriter.write(
            topic: request.topic,
            script: script,
            storyboard: storyboard,
            preset: request.preset,
            channel: request.channel,
            series: request.seriesName,
            target: request.target,
            credits: credits
        )
        if request.useLocalAI {
            let status = await LocalAIClient.shared.probe()
            if let model = status.ollamaModel,
               let raw = await LocalAIClient.shared.generatePublishCopy(
                topic: request.topic,
                script: script,
                channel: request.channel,
                model: model
               ) {
                pack = PublishPackWriter.parseModelOutput(raw, fallback: pack)
            }
        }
        let headlines = [
            PublishPackWriter.thumbnailHeadline(from: script.hook),
            PublishPackWriter.thumbnailHeadline(from: request.topic),
            PublishPackWriter.thumbnailHeadline(from: script.body.first ?? script.hook)
        ]
        var thumbPaths: [String] = []
        for (index, headline) in headlines.enumerated() {
            let thumbURL = assetsDir.appendingPathComponent("thumbnail-\(index + 1).jpg")
            ThumbnailRenderer.render(hook: headline, channel: request.channel, preset: request.preset, to: thumbURL)
            thumbPaths.append(thumbURL.path)
        }
        pack.thumbnailPaths = thumbPaths
        pack.thumbnailPath = thumbPaths.first
        if request.exportSRT {
            let srtURL = assetsDir.appendingPathComponent("captions.srt")
            try? SRTWriter.write(cues: project.captions, to: srtURL)
            pack.srtPath = srtURL.path
        }
        project.publishPack = pack
        completed.append(.package)
        try ProjectStore.save(project)

        try Task.checkCancellation()
        await emit(.export, "Writing H.264 yuv420p +faststart MP4")
        let exportURL = try ProjectStore.exportURL(presetID: request.preset.id, topic: request.topic)
        if let one = oneEncodeURL {
            if FileManager.default.fileExists(atPath: exportURL.path) {
                try? FileManager.default.removeItem(at: exportURL)
            }
            try FileManager.default.createDirectory(at: exportURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: one, to: exportURL)
        } else {
            let built = try await CompositionBuilder.build(plan: plan, workDir: assetsDir)
            try await VideoExporter.export(
                built: built,
                to: exportURL,
                fallbackClips: renderedClips,
                fallbackAudio: [voiceURL, musicURL]
            )
        }
        project.exportPath = exportURL.path
        var copiedThumbs: [String] = []
        let exportBase = exportURL.deletingPathExtension()
        for (index, thumb) in thumbPaths.enumerated() {
            let dest = exportBase.deletingLastPathComponent()
                .appendingPathComponent("\(exportBase.lastPathComponent)-thumb\(index + 1).jpg")
            copyReplacing(URL(fileURLWithPath: thumb), to: dest)
            copiedThumbs.append(dest.path)
        }
        if let first = copiedThumbs.first {
            let dest = exportURL.deletingPathExtension().appendingPathExtension("jpg")
            copyReplacing(URL(fileURLWithPath: first), to: dest)
            pack.thumbnailPath = dest.path
        }
        pack.thumbnailPaths = copiedThumbs
        if let srt = pack.srtPath {
            let dest = exportURL.deletingPathExtension().appendingPathExtension("srt")
            copyReplacing(URL(fileURLWithPath: srt), to: dest)
            pack.srtPath = dest.path
        }
        if let data = try? JSONEncoder().encode(pack) {
            try? data.write(to: exportURL.deletingPathExtension().appendingPathExtension("json"))
        }
        if let data = try? JSONEncoder().encode(ledger) {
            try? data.write(to: exportURL.deletingPathExtension().appendingPathExtension("credits.json"))
        }
        project.publishPack = pack
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

    private func spokenText(_ script: GeneratedScript, pause: Double) -> String {
        let gap = pause > 0.05 ? String(repeating: ". ", count: max(1, Int(pause * 4))) : " "
        let joined = script.spokenLines.joined(separator: gap)
        return joined.replacingOccurrences(of: ", ", with: ", … ")
    }

    private func resolveMusic(channel: ChannelKit, preset: Preset, to url: URL, useLocalAI: Bool) async throws -> String {
        if let folder = channel.musicFolderPath, !folder.isEmpty {
            let dir = URL(fileURLWithPath: folder)
            let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            let audio = files.filter { ["wav", "m4a", "mp3", "aiff", "caf"].contains($0.pathExtension.lowercased()) }
            if let pick = audio.first {
                if FileManager.default.fileExists(atPath: url.path) {
                    try? FileManager.default.removeItem(at: url)
                }
                try FileManager.default.copyItem(at: pick, to: url)
                return "user-folder"
            }
        }
        if useLocalAI, await ACEStepClient.shared.generateBed(mood: preset.music.mood.rawValue, bpm: preset.music.bpm, to: url) {
            return "ace-step"
        }
        try MusicBedSynthesizer.writeLoop(mood: preset.music.mood, bpm: preset.music.bpm, to: url)
        return "bundled-bed"
    }

    private func copyReplacing(_ from: URL, to dest: URL) {
        if FileManager.default.fileExists(atPath: dest.path) {
            try? FileManager.default.removeItem(at: dest)
        }
        try? dest.deletingLastPathComponent().createDirectoryIfNeeded()
        try? FileManager.default.copyItem(at: from, to: dest)
    }
}

private extension URL {
    func createDirectoryIfNeeded() throws {
        try FileManager.default.createDirectory(at: self, withIntermediateDirectories: true)
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

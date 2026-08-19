import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppState: ObservableObject {
    @Published var presets: [Preset] = []
    @Published var selectedPreset: Preset?
    @Published var project = Project()
    @Published var topic: String = ""
    @Published var aspectOverride: AspectRatio?
    @Published var durationOverride: Int?
    @Published var useUnsplash = false
    @Published var usePexels = true
    @Published var usePixabay = true
    @Published var allowCards = false
    @Published var captionStyleID: String = CaptionCatalog.resolve(id: UserDefaults.standard.string(forKey: "reelforge.captionStyleID"))
    @Published var useLocalAI = true
    @Published var burnCaptions = true
    @Published var exportSRT = true
    @Published var voiceIdentifier: String?
    @Published var voiceSpeed: Double = 1.0
    @Published var beatPause: Double = 0.15
    @Published var channelType: ChannelType = .facelessFacts
    @Published var target: VideoTarget = .short
    @Published var language: ContentLanguage = .english
    @Published var seriesName: String = ""
    @Published var batchText: String = ""
    @Published var batchItems: [BatchItem] = []
    @Published var channelKit = ChannelKit()
    @Published var footageURLs: [URL] = []
    @Published var voiceoverURL: URL?
    @Published var progress = PipelineProgress.idle
    @Published var isGenerating = false
    @Published var previewURL: URL?
    @Published var exportURL: URL?
    @Published var lastError: String?
    @Published var showSettings = false
    @Published var localStatus = LocalAIStatus()
    @Published var unsplashConfigured = false
    @Published var pexelsConfigured = false
    @Published var pixabayConfigured = false
    @Published var captionLooks: [CaptionLook] = (try? CaptionCatalog.load()) ?? []
    @Published var modelsDir: String = UserDefaults.standard.string(forKey: "reelforge.modelsDir") ?? ""
    @Published var search = ""
    @Published var player: AVPlayer?
    @Published var awaitingAccept = false
    @Published var deskHook = ""
    @Published var deskBody: [EditableLine] = []
    @Published var deskCTA = ""

    private var generateTask: Task<Void, Never>?
    private var pendingRequest: GenerateRequest?
    private let director = Director()

    var filteredPresets: [Preset] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return presets }
        return presets.filter {
            $0.name.lowercased().contains(q) || $0.tagline.lowercased().contains(q) || $0.id.contains(q)
        }
    }

    var activePreset: Preset? { selectedPreset ?? presets.first }

    var resolvedAspect: AspectRatio {
        aspectOverride ?? channelKit.defaultAspect ?? (target == .longForm ? .landscape : activePreset?.aspect) ?? .vertical
    }

    var resolvedDuration: Int {
        if let durationOverride { return durationOverride }
        let presetDuration = activePreset?.durationSec ?? 30
        switch target {
        case .short:
            if presetDuration >= 180 { return 45 }
            return min(60, max(15, presetDuration))
        case .longForm:
            return presetDuration >= 180 ? presetDuration : target.defaultDuration
        }
    }

    var publishPack: PublishPack? { project.publishPack }

    var canGenerate: Bool {
        !topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && activePreset != nil
            && !isGenerating
            && !awaitingAccept
    }

    init() {
        loadPresets()
        channelKit = ChannelStore.load()
        applyChannelDefaults()
        refreshStatus()
        if voiceIdentifier == nil {
            voiceIdentifier = channelKit.defaultVoice ?? SpeechService.defaultVoice()?.identifier
        }
    }

    func loadPresets() {
        do {
            let loaded = try PresetStore.load()
            presets = loaded
            if selectedPreset == nil {
                selectedPreset = loaded.first { $0.id == "viral-hook" } ?? loaded.first
            }
            if UserDefaults.standard.string(forKey: "reelforge.captionStyleID") == nil,
               let preset = selectedPreset {
                captionStyleID = CaptionCatalog.defaultID(forPreset: preset.id)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refreshStatus() {
        unsplashConfigured = KeychainStore.unsplashAccessKey != nil
        pexelsConfigured = KeychainStore.pexelsAPIKey != nil
        pixabayConfigured = KeychainStore.pixabayAPIKey != nil
        Task {
            localStatus = await LocalAIClient.shared.probe()
        }
    }

    func newProject() {
        cancel()
        project = Project()
        topic = ""
        footageURLs = []
        voiceoverURL = nil
        previewURL = nil
        exportURL = nil
        lastError = nil
        progress = .idle
        player?.pause()
        player = nil
        aspectOverride = nil
        durationOverride = nil
        awaitingAccept = false
        pendingRequest = nil
        deskHook = ""
        deskBody = []
        deskCTA = ""
    }

    func generate() {
        guard let preset = activePreset else { return }
        let brief = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !brief.isEmpty else { return }
        if let warning = NicheGuard.warning(for: brief) {
            lastError = warning
            return
        }
        isGenerating = true
        awaitingAccept = false
        lastError = nil
        progress = PipelineProgress(current: .script, detail: "Starting director…", fraction: 0.02)
        var next = project
        next.topic = brief
        next.presetID = preset.id
        next.aspectOverride = aspectOverride
        next.durationOverride = durationOverride
        next.useUnsplash = useUnsplash
        next.usePexels = usePexels
        next.captionStyleID = captionStyleID
        next.allowCards = allowCards
        next.useLocalAI = useLocalAI
        next.burnCaptions = burnCaptions
        next.exportSRT = exportSRT
        next.voiceIdentifier = voiceIdentifier
        next.voiceSpeed = voiceSpeed
        next.beatPause = beatPause
        next.channelType = channelType
        next.target = target
        next.language = language
        next.seriesName = seriesName.isEmpty ? nil : seriesName
        next.name = brief
        persistChannel()
        project = next

        let request = GenerateRequest(
            topic: brief,
            preset: preset,
            aspect: resolvedAspect,
            duration: resolvedDuration,
            voiceIdentifier: voiceIdentifier,
            voiceSpeed: voiceSpeed,
            beatPause: beatPause,
            voiceoverURL: voiceoverURL,
            footageURLs: footageURLs,
            useUnsplash: useUnsplash,
            usePexels: usePexels,
            usePixabay: usePixabay,
            useLocalAI: useLocalAI,
            burnCaptions: burnCaptions,
            exportSRT: exportSRT,
            unsplashKey: KeychainStore.unsplashAccessKey,
            pexelsKey: KeychainStore.pexelsAPIKey,
            pixabayKey: KeychainStore.pixabayAPIKey,
            captionStyleID: captionStyleID,
            allowCards: allowCards,
            channelType: channelType,
            target: target,
            seriesName: seriesName.isEmpty ? nil : seriesName,
            channel: channelKit,
            project: next
        )

        pendingRequest = request
        generateTask = Task { [director] in
            do {
                let draft = try await director.draft(request) { [weak self] snapshot in
                    self?.progress = snapshot
                }
                guard !Task.isCancelled else { return }
                self.project = draft.project
                self.populateDesk(from: draft.project)
                self.awaitingAccept = true
                self.isGenerating = false
                self.progress.detail = "Accept the script to render. Nothing exports until you click Accept."
            } catch is CancellationError {
                self.isGenerating = false
                self.progress.detail = "Cancelled."
            } catch {
                self.lastError = error.localizedDescription
                self.progress.isFailed = true
                self.progress.detail = error.localizedDescription
                self.isGenerating = false
            }
        }
    }

    func acceptScript() {
        guard awaitingAccept, var request = pendingRequest else { return }
        if let warning = NicheGuard.warning(for: "\(deskHook) \(topic)") {
            lastError = warning
            return
        }
        if HookRules.isForbiddenOpen(deskHook) {
            lastError = StoryboardError.missingHook.errorDescription
            return
        }
        guard applyDeskToProject() else { return }
        var next = project
        next.scriptAccepted = true
        next.voiceIdentifier = voiceIdentifier
        project = next
        request.project = next
        request.voiceIdentifier = voiceIdentifier
        pendingRequest = request
        awaitingAccept = false
        isGenerating = true
        lastError = nil

        generateTask = Task { [director] in
            do {
                let result = try await director.compose(request) { [weak self] snapshot in
                    self?.progress = snapshot
                }
                guard !Task.isCancelled else { return }
                self.project = result.project
                self.exportURL = result.exportURL
                self.previewURL = result.exportURL
                self.attachPlayer(result.exportURL)
                self.isGenerating = false
                self.advanceBatchIfNeeded()
            } catch is CancellationError {
                self.isGenerating = false
                self.progress.detail = "Cancelled."
            } catch {
                self.lastError = error.localizedDescription
                self.progress.isFailed = true
                self.progress.detail = error.localizedDescription
                self.isGenerating = false
            }
        }
    }

    func populateDesk(from project: Project) {
        deskHook = project.script?.hook ?? ""
        deskBody = (project.script?.body ?? []).map { EditableLine(text: $0) }
        deskCTA = project.script?.cta ?? ""
    }

    @discardableResult
    func applyDeskToProject() -> Bool {
        let script = GeneratedScript(
            hook: deskHook,
            body: deskBody.map(\.text).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
            cta: deskCTA,
            source: .user
        )
        project.script = script
        guard let preset = activePreset else {
            lastError = "Pick a preset before accepting the script."
            return false
        }
        do {
            var board = try StoryboardBuilder.build(
                script: script,
                preset: preset,
                duration: Double(resolvedDuration)
            )
            board = StoryboardBuilder.appendingOutro(
                board,
                channelName: channelKit.name,
                enabled: channelKit.outroEnabled
            )
            project.storyboard = board
            let fresh = CaptionSplitter.cues(
                from: script,
                duration: board.duration,
                maxWordsPerCard: CaptionSafeArea.maxWords(
                    forPresetID: preset.id,
                    requested: CaptionCatalog.look(id: captionStyleID).maxWords
                ),
                storyboard: board
            )
            if project.captions.count == fresh.count {
                var merged = fresh
                for index in merged.indices {
                    merged[index].text = project.captions[index].text
                }
                project.captions = merged
            } else if project.captions.isEmpty {
                project.captions = fresh
            }
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func addDeskBodyLine() {
        deskBody.append(EditableLine(text: ""))
    }

    func cancel() {
        generateTask?.cancel()
        generateTask = nil
        isGenerating = false
        awaitingAccept = false
    }

    func attachPlayer(_ url: URL) {
        player?.pause()
        let item = AVPlayerItem(url: url)
        let next = AVPlayer(playerItem: item)
        next.play()
        player = next
    }

    func revealExport() {
        guard let exportURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([exportURL])
    }

    func addDroppedURLs(_ urls: [URL]) {
        for url in urls {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                let kids = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
                addDroppedURLs(kids)
                continue
            }
            let ext = url.pathExtension.lowercased()
            if ["wav", "m4a", "mp3", "aiff", "caf", "aac"].contains(ext) {
                _ = url.startAccessingSecurityScopedResource()
                voiceoverURL = url
            } else if ["mp4", "mov", "m4v", "jpg", "jpeg", "png", "heic", "webp"].contains(ext) {
                if !footageURLs.contains(url) {
                    _ = url.startAccessingSecurityScopedResource()
                    footageURLs.append(url)
                }
            }
        }
    }

    func pickMedia() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.movie, .image, .audio, .folder]
        if panel.runModal() == .OK {
            addDroppedURLs(panel.urls)
        }
    }

    func persistChannel() {
        ChannelStore.save(channelKit)
    }

    func selectPreset(_ preset: Preset) {
        selectedPreset = preset
        captionStyleID = CaptionCatalog.defaultID(forPreset: preset.id)
        persistCaptionStyle()
    }

    func persistCaptionStyle() {
        UserDefaults.standard.set(captionStyleID, forKey: "reelforge.captionStyleID")
    }

    func applyChannelDefaults() {
        if selectedPreset == nil || selectedPreset?.id == "viral-hook" {
            if let match = presets.first(where: { $0.id == channelKit.defaultPresetID }) {
                selectedPreset = match
            }
        }
        if let aspect = channelKit.defaultAspect {
            aspectOverride = aspect
        }
        if let voice = channelKit.defaultVoice, !voice.isEmpty {
            voiceIdentifier = voice
        }
    }

    func pickMusicFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            channelKit.musicFolderPath = url.path
            persistChannel()
        }
    }

    func pickModelsDir() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use this folder"
        if panel.runModal() == .OK, let url = panel.url {
            modelsDir = url.path
            UserDefaults.standard.set(url.path, forKey: "reelforge.modelsDir")
            refreshStatus()
        }
    }

    func pickChannelLogo() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.png, .jpeg, .heic, .webP]
        if panel.runModal() == .OK, let url = panel.url {
            if let relative = ChannelStore.saveLogo(url) {
                channelKit.logoRelativePath = relative
                persistChannel()
            }
        }
    }

    func selectChannelType(_ type: ChannelType) {
        channelType = type
        if let match = presets.first(where: { $0.id == type.suggestedPresetID }) {
            selectedPreset = match
        }
    }

    func generateBatch() {
        let topics = batchText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard topics.count >= 2 else {
            lastError = "Paste at least two topics to batch."
            return
        }
        batchItems = topics.map { BatchItem(topic: $0) }
        startNextBatchDraft()
    }

    private func startNextBatchDraft() {
        guard let index = batchItems.firstIndex(where: { $0.status == .idle }) else { return }
        topic = batchItems[index].topic
        project = Project()
        batchItems[index].status = .running
        generate()
    }

    private func advanceBatchIfNeeded() {
        if let index = batchItems.firstIndex(where: { $0.status == .running }) {
            batchItems[index].status = lastError == nil ? .done : .failed
            batchItems[index].exportURL = exportURL
        }
        startNextBatchDraft()
    }
}

struct EditableLine: Identifiable, Equatable {
    var id = UUID()
    var text: String
}

struct BatchItem: Identifiable, Equatable {
    var id = UUID()
    var topic: String
    var status: Status = .idle
    var exportURL: URL?

    enum Status: String {
        case idle, running, done, failed
    }
}

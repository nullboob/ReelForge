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
    @Published var useUnsplash = true
    @Published var useLocalAI = true
    @Published var voiceIdentifier: String?
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
    @Published var search = ""
    @Published var player: AVPlayer?

    private var generateTask: Task<Void, Never>?
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
        aspectOverride ?? activePreset?.aspect ?? .vertical
    }

    var resolvedDuration: Int {
        durationOverride ?? activePreset?.durationSec ?? 15
    }

    var canGenerate: Bool {
        !topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && activePreset != nil && !isGenerating
    }

    init() {
        loadPresets()
        refreshStatus()
        voiceIdentifier = SpeechService.defaultVoice()?.identifier
    }

    func loadPresets() {
        do {
            let loaded = try PresetStore.load()
            presets = loaded
            if selectedPreset == nil {
                selectedPreset = loaded.first { $0.id == "viral-hook" } ?? loaded.first
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refreshStatus() {
        unsplashConfigured = KeychainStore.unsplashAccessKey != nil
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
    }

    func generate() {
        guard let preset = activePreset else { return }
        let brief = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !brief.isEmpty else { return }
        isGenerating = true
        lastError = nil
        progress = PipelineProgress(current: .script, detail: "Starting director…", fraction: 0.02)
        var next = project
        next.topic = brief
        next.presetID = preset.id
        next.aspectOverride = aspectOverride
        next.durationOverride = durationOverride
        next.useUnsplash = useUnsplash
        next.useLocalAI = useLocalAI
        next.voiceIdentifier = voiceIdentifier
        next.name = brief
        project = next

        let request = GenerateRequest(
            topic: brief,
            preset: preset,
            aspect: resolvedAspect,
            duration: resolvedDuration,
            voiceIdentifier: voiceIdentifier,
            voiceoverURL: voiceoverURL,
            footageURLs: footageURLs,
            useUnsplash: useUnsplash,
            useLocalAI: useLocalAI,
            unsplashKey: KeychainStore.unsplashAccessKey,
            project: next
        )

        generateTask = Task { [director] in
            do {
                let result = try await director.run(request) { [weak self] snapshot in
                    self?.progress = snapshot
                }
                guard !Task.isCancelled else { return }
                self.project = result.project
                self.exportURL = result.exportURL
                self.previewURL = result.exportURL
                self.attachPlayer(result.exportURL)
                self.isGenerating = false
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

    func cancel() {
        generateTask?.cancel()
        generateTask = nil
        isGenerating = false
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
}

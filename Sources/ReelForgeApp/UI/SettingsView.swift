import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @State private var unsplash = ""
    @State private var pexels = ""
    @State private var pixabay = ""
    @State private var youtube = ""
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Settings")
                    .font(.system(size: 20, weight: .semibold))
                Spacer()
                Button("Done") {
                    persistKeys()
                    state.persistChannel()
                    state.applyChannelDefaults()
                    state.showSettings = false
                }
                .buttonStyle(GhostButtonStyle())
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    keysSection
                    channelSection
                    servicesSection
                    workflowsSection
                    attributionSection
                }
            }
        }
        .padding(28)
        .frame(width: 620, height: 760)
        .background(RFTheme.bg)
        .onAppear {
            unsplash = KeychainStore.string(account: KeychainStore.unsplashAccount) ?? ""
            pexels = KeychainStore.string(account: KeychainStore.pexelsAccount) ?? ""
            pixabay = KeychainStore.string(account: KeychainStore.pixabayAccount) ?? ""
            youtube = KeychainStore.string(account: KeychainStore.youtubeAccount) ?? ""
            state.refreshStatus()
        }
    }

    private var keysSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Keys")
            labeledField("Unsplash access key", text: $unsplash)
            labeledField("Pexels API key (REELFORGE_PEXELS_API_KEY)", text: $pexels)
            labeledField("Pixabay API key (optional second stock source)", text: $pixabay)
            labeledField("YouTube Data API key (upload later)", text: $youtube)
            Text("Pexels Videos is first. Pixabay is the second free source. Cards are last-resort and will not export as a finished Short unless you opt in. Unsplash stays off by default.")
                .font(.system(size: 11))
                .foregroundStyle(RFTheme.muted)
            HStack {
                Button("Save keys") {
                    persistKeys()
                    saved = true
                }
                .buttonStyle(PrimaryButtonStyle())
                if saved {
                    Text("Saved")
                        .foregroundStyle(.green)
                        .font(.system(size: 12, weight: .medium))
                }
            }
        }
    }

    private var channelSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Channel kit")
            TextField("Channel name", text: $state.channelKit.name)
                .textFieldStyle(.roundedBorder)
            HStack {
                ColorPicker("Primary", selection: Binding(
                    get: { Color(hex: state.channelKit.primaryHex) },
                    set: { state.channelKit.primaryHex = $0.hexString }
                ))
                ColorPicker("Accent", selection: Binding(
                    get: { Color(hex: state.channelKit.accentHex) },
                    set: { state.channelKit.accentHex = $0.hexString }
                ))
            }
            HStack {
                Text("Logo")
                Spacer()
                if let name = state.channelKit.logoRelativePath {
                    Text(name).foregroundStyle(RFTheme.muted)
                }
                Button("Drop / choose") { state.pickChannelLogo() }
                    .buttonStyle(GhostButtonStyle())
            }
            Text("The hook scene always opens the video. Channel intro is not prepended (no logo-first open).")
                .font(.system(size: 11))
                .foregroundStyle(RFTheme.muted)
            Toggle("Outro subscribe card", isOn: $state.channelKit.outroEnabled)
            HStack {
                Text("Imported music folder")
                Spacer()
                if let path = state.channelKit.musicFolderPath, !path.isEmpty {
                    Text(URL(fileURLWithPath: path).lastPathComponent)
                        .foregroundStyle(RFTheme.muted)
                }
                Button("Choose") { state.pickMusicFolder() }
                    .buttonStyle(GhostButtonStyle())
            }
            Picker("Default voice", selection: Binding(
                get: { state.channelKit.defaultVoice ?? "" },
                set: { state.channelKit.defaultVoice = $0.isEmpty ? nil : $0 }
            )) {
                Text("System / auto").tag("")
                ForEach(SpeechService.allVoices()) { voice in
                    Text(voice.name).tag(voice.id)
                }
            }
            Picker("Default preset", selection: $state.channelKit.defaultPresetID) {
                ForEach(state.presets) { preset in
                    Text(preset.name).tag(preset.id)
                }
            }
            Picker("Default aspect", selection: Binding(
                get: { state.channelKit.defaultAspect },
                set: { state.channelKit.defaultAspect = $0 }
            )) {
                Text("Follow preset").tag(Optional<AspectRatio>.none)
                Text("9:16 Short").tag(Optional(AspectRatio.vertical))
                Text("16:9 Long").tag(Optional(AspectRatio.landscape))
                Text("1:1").tag(Optional(AspectRatio.square))
            }
            Text("Applied on Accept: colors, logo after 1.5s, outro, default voice, preset, aspect. Music is bundled beds or your imported folder — never CapCut/TikTok tracks.")
                .font(.system(size: 11))
                .foregroundStyle(RFTheme.muted)
        }
        .onChange(of: state.channelKit) { _, _ in
            state.persistChannel()
        }
    }

    private var servicesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Local services")
            statusRow("Kokoro-82M", state.localStatus.kokoro, "http://127.0.0.1:8880")
            statusRow("AVSpeech", true, "fallback, always available")
            statusRow("ComfyUI", state.localStatus.comfyUI, state.localStatus.comfyDetail.isEmpty ? "http://127.0.0.1:8188" : state.localStatus.comfyDetail)
            statusRow("ComfyUI video (LTX / I2V)", state.localStatus.canComfyVideo, "user workflow or LTX nodes")
            statusRow("Ollama", state.localStatus.ollama, state.localStatus.ollamaModel ?? "http://127.0.0.1:11434")
            statusRow("Automatic1111", state.localStatus.automatic1111, "http://127.0.0.1:7860")
            statusRow("Local whisper", state.localStatus.whisper, "http://127.0.0.1:9000")
            Text("Preferred TTS: Kokoro-FastAPI at http://127.0.0.1:8880/v1/audio/speech. AVSpeech if Kokoro is down. Piper is not embedded (GPL-3.0). Music is bundled original-safe beds or your imported folder — ACE-Step is not on the Director path.")
                .font(.system(size: 11))
                .foregroundStyle(RFTheme.muted)
            Button("Re-scan") { state.refreshStatus() }
                .buttonStyle(GhostButtonStyle())
        }
    }

    private var workflowsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("ComfyUI workflows")
            Text("ComfyUI / LTX are optional sidecars. Stock (Pexels) is first. ReelForge does not vendor ComfyUI or GPL ffmpeg. Export is AVFoundation / VideoToolbox.")
                .font(.system(size: 11))
                .foregroundStyle(RFTheme.muted)
        }
    }

    private var attributionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Attribution")
            Text("Pexels and Unsplash credits are stored on project JSON. They are not burned into the video.")
                .font(.system(size: 11))
                .foregroundStyle(RFTheme.muted)
        }
    }

    private func persistKeys() {
        KeychainStore.set(unsplash, account: KeychainStore.unsplashAccount)
        KeychainStore.set(pexels, account: KeychainStore.pexelsAccount)
        KeychainStore.set(pixabay, account: KeychainStore.pixabayAccount)
        KeychainStore.set(youtube, account: KeychainStore.youtubeAccount)
        state.refreshStatus()
    }

    private func labeledField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
            SecureField("Paste key", text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(1.1)
            .foregroundStyle(RFTheme.muted)
    }

    private func statusRow(_ name: String, _ on: Bool, _ detail: String) -> some View {
        HStack {
            Circle().fill(on ? Color.green : RFTheme.muted).frame(width: 8, height: 8)
            Text(name)
            Spacer()
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(RFTheme.muted)
        }
        .padding(8)
        .rfCard(radius: 10)
    }
}

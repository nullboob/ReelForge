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
                    state.persistComfySettings()
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
                    modelManagerSection
                    servicesSection
                    comfySection
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
            statusRow("edge-tts CLI", SpeechService.edgeTTSCLI() != nil, "user-installed, not vendored")
            statusRow("Ollama", state.localStatus.ollama, state.localStatus.ollamaModel ?? "http://127.0.0.1:11434")
            statusRow("ACE-Step", state.localStatus.aceStep, "http://127.0.0.1:7865")
            statusRow("Local whisper", state.localStatus.whisper, "http://127.0.0.1:9000")
            Text("Voice: Kokoro-FastAPI at :8880, then a user-installed edge-tts CLI, then the Mac’s basic voice. Piper/espeak are not vendored. GPU packs are optional.")
                .font(.system(size: 11))
                .foregroundStyle(RFTheme.muted)
            Button("Re-scan") { state.refreshStatus() }
                .buttonStyle(GhostButtonStyle())
        }
    }

    private var comfySection: some View {
        DisclosureGroup("Advanced: I already run ComfyUI") {
        VStack(alignment: .leading, spacing: 8) {
            Text("Not required. The sold app uses native inference when models are Ready. This only talks to a sidecar you already started.")
                .font(.system(size: 11))
                .foregroundStyle(RFTheme.muted)
            TextField("http://127.0.0.1:8188", text: $state.comfyUrl)
                .textFieldStyle(.roundedBorder)
                .onChange(of: state.comfyUrl) { _, _ in state.persistComfySettings() }
            Picker("Local gen mode", selection: $state.localMode) {
                Text("Stock first").tag(LocalGenMode.stockFirst.rawValue)
                Text("Local Fast").tag(LocalGenMode.localFast.rawValue)
                Text("Local Quality").tag(LocalGenMode.localQuality.rawValue)
            }
            .onChange(of: state.localMode) { _, _ in state.persistComfySettings() }
            HStack(spacing: 8) {
                chip("Comfy", state.localStatus.comfy)
                chip("LTX", state.localStatus.comfyLTX)
                chip("Wan", state.localStatus.comfyWan)
                chip("Qwen", state.localStatus.comfyQwen)
            }
            filenameField("LTX checkpoint filename", text: $state.ltxCkpt)
            filenameField("LTX LoRA filename", text: $state.ltxLora)
            filenameField("Wan UNET filename", text: $state.wanCkpt)
            filenameField("Wan LightX2V LoRA", text: $state.wanLora)
            filenameField("Qwen Image UNET", text: $state.qwenCkpt)
            filenameField("Qwen Lightning LoRA", text: $state.qwenLora)
            Button("Probe ComfyUI") {
                state.persistComfySettings()
                state.refreshStatus()
            }
            .buttonStyle(GhostButtonStyle())
        }
        }
    }

    private func chip(_ title: String, _ on: Bool) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((on ? Color.green : RFTheme.muted).opacity(on ? 0.18 : 0.12), in: Capsule())
            .foregroundStyle(on ? Color.green.opacity(0.9) : RFTheme.muted)
    }

    private var modelManagerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Model Manager")
            Text("Creator/Studio optional. Point at weights you already have, or use the first-run wizard. The installer never bundles diffusion models.")
                .font(.system(size: 11))
                .foregroundStyle(RFTheme.muted)
            HStack {
                TextField("Folder that already has .safetensors / .gguf", text: $state.modelsDir)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: state.modelsDir) { _, value in
                        UserDefaults.standard.set(value, forKey: "reelforge.modelsDir")
                    }
                Button("Choose") { state.pickModelsDir() }
                    .buttonStyle(GhostButtonStyle())
            }
            Button("Scan now") {
                UserDefaults.standard.set(state.modelsDir, forKey: "reelforge.modelsDir")
                state.refreshStatus()
            }
            .buttonStyle(GhostButtonStyle())
            ForEach(state.localStatus.models.slots) { slot in
                HStack {
                    Circle().fill(slot.ready ? Color.green : RFTheme.muted).frame(width: 8, height: 8)
                    Text(slot.name)
                    Spacer()
                    Text(slot.ready ? "Ready" : "Missing")
                        .font(.system(size: 11))
                        .foregroundStyle(RFTheme.muted)
                }
                .padding(8)
                .rfCard(radius: 10)
            }
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

    private func filenameField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
        }
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

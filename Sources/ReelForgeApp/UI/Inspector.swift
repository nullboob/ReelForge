import AVFoundation
import SwiftUI

struct Inspector: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                section("Create") {
                    labeled("Channel type") {
                        Picker("", selection: $state.channelType) {
                            ForEach(ChannelType.allCases, id: \.self) { type in
                                Text(type.displayName).tag(type)
                            }
                        }
                        .labelsHidden()
                        .onChange(of: state.channelType) { _, type in
                            state.selectChannelType(type)
                        }
                    }
                    labeled("Target") {
                        Picker("", selection: $state.target) {
                            ForEach(VideoTarget.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    labeled("Language") {
                        Picker("", selection: $state.language) {
                            Text("English").tag(ContentLanguage.english)
                        }
                        .labelsHidden()
                    }
                    labeled("Series / pillar") {
                        TextField("Optional series name", text: $state.seriesName)
                            .textFieldStyle(.roundedBorder)
                    }
                    Text("Topic or full script")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(RFTheme.muted)
                    ZStack(alignment: .topLeading) {
                        if state.topic.isEmpty {
                            Text("3 reasons your morning walk beats the gym")
                                .foregroundStyle(RFTheme.muted.opacity(0.7))
                                .padding(10)
                        }
                        TextEditor(text: $state.topic)
                            .font(.system(size: 13))
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 110)
                            .padding(6)
                    }
                    .background(RFTheme.elevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(RFTheme.border, lineWidth: 1)
                    )
                }

                section("Format") {
                    labeled("Aspect") {
                        Picker("", selection: aspectBinding) {
                            Text("Auto").tag(Optional<AspectRatio>.none)
                            ForEach(AspectRatio.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    labeled("Duration") {
                        Picker("", selection: durationBinding) {
                            Text("Preset").tag(Optional<Int>.none)
                            ForEach(state.target.durationChoices, id: \.self) { seconds in
                                Text(seconds >= 60 ? "\(seconds / 60)m" : "\(seconds)s").tag(Optional(seconds))
                            }
                        }
                        .labelsHidden()
                    }
                }

                section("Voice") {
                    Text("Engine: \(state.localStatus.ttsEngine)")
                        .font(.system(size: 11))
                        .foregroundStyle(RFTheme.gold)
                    Picker("Voice", selection: voiceBinding) {
                        Text("Auto (Kokoro → Piper → Mac)").tag(Optional<String>.none)
                        ForEach(SpeechService.allVoices()) { voice in
                            Text(voice.name).tag(Optional(voice.id))
                        }
                    }
                    .labelsHidden()
                    labeled("Speed \(String(format: "%.2f", state.voiceSpeed))") {
                        Slider(value: $state.voiceSpeed, in: 0.7...1.35)
                    }
                    labeled("Pause between beats \(String(format: "%.1f", state.beatPause))s") {
                        Slider(value: $state.beatPause, in: 0...0.8)
                    }
                }

                section("Captions") {
                    Toggle("Burn captions into the video", isOn: $state.burnCaptions)
                    Toggle("Also export sidecar SRT", isOn: $state.exportSRT)
                }

                section("Sources") {
                    Toggle("Pexels stock video", isOn: $state.usePexels)
                    if state.usePexels && !state.pexelsConfigured {
                        Button("Add Pexels key in Settings") { state.showSettings = true }
                            .buttonStyle(GhostButtonStyle())
                    }
                    Toggle("Unsplash stills", isOn: $state.useUnsplash)
                    Toggle("Use ComfyUI / local AI if available", isOn: $state.useLocalAI)
                    DropZone()
                    if let voice = state.voiceoverURL {
                        Text("VO: \(voice.lastPathComponent) (wins over TTS)")
                            .font(.system(size: 11))
                            .foregroundStyle(RFTheme.muted)
                    }
                    if !state.footageURLs.isEmpty {
                        Text("\(state.footageURLs.count) local files")
                            .font(.system(size: 11))
                            .foregroundStyle(RFTheme.muted)
                    }
                }

                section("Batch") {
                    Text("One topic per line. Generate all.")
                        .font(.system(size: 11))
                        .foregroundStyle(RFTheme.muted)
                    TextEditor(text: $state.batchText)
                        .font(.system(size: 12))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 72)
                        .padding(6)
                        .background(RFTheme.elevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Button("Generate all") { state.generateBatch() }
                        .buttonStyle(GhostButtonStyle())
                        .disabled(state.isGenerating)
                    ForEach(state.batchItems) { item in
                        HStack {
                            Circle().fill(batchColor(item.status)).frame(width: 7, height: 7)
                            Text(item.topic).lineLimit(1)
                            Spacer()
                            Text(item.status.rawValue).foregroundStyle(RFTheme.muted)
                        }
                        .font(.system(size: 11))
                    }
                }

                if let error = state.lastError {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(RFTheme.accent)
                }

                VStack(spacing: 10) {
                    Button(state.isGenerating ? "Cancel" : "Generate") {
                        if state.isGenerating { state.cancel() } else { state.generate() }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!state.canGenerate && !state.isGenerating)
                    Button("Export / Reveal") { state.revealExport() }
                        .buttonStyle(GhostButtonStyle())
                        .disabled(state.exportURL == nil)
                }
            }
            .padding(18)
        }
        .background(RFTheme.bg)
        .toggleStyle(.switch)
    }

    private var aspectBinding: Binding<AspectRatio?> {
        Binding(get: { state.aspectOverride }, set: { state.aspectOverride = $0 })
    }

    private var durationBinding: Binding<Int?> {
        Binding(get: { state.durationOverride }, set: { state.durationOverride = $0 })
    }

    private var voiceBinding: Binding<String?> {
        Binding(get: { state.voiceIdentifier }, set: { state.voiceIdentifier = $0 })
    }

    private func batchColor(_ status: BatchItem.Status) -> Color {
        switch status {
        case .idle: return RFTheme.muted
        case .running: return RFTheme.gold
        case .done: return .green
        case .failed: return RFTheme.accent
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(RFTheme.muted)
            content()
        }
    }

    private func labeled(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(RFTheme.muted)
            content()
        }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                LinearGradient(colors: [RFTheme.accent, Color(hex: "#FF7A59")], startPoint: .leading, endPoint: .trailing)
                    .opacity(configuration.isPressed ? 0.8 : 1)
            )
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

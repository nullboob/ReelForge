import AVFoundation
import SwiftUI

struct Inspector: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                section("Brief") {
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
                            .frame(minHeight: 120)
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
                            Text("Preset").tag(Optional<AspectRatio>.none)
                            ForEach(AspectRatio.allCases, id: \.self) { aspect in
                                Text(aspect.rawValue).tag(Optional(aspect))
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    labeled("Duration") {
                        Picker("", selection: durationBinding) {
                            Text("Preset").tag(Optional<Int>.none)
                            Text("15s").tag(Optional(15))
                            Text("30s").tag(Optional(30))
                            Text("60s").tag(Optional(60))
                        }
                        .labelsHidden()
                    }
                }

                section("Voice") {
                    Picker("Voice", selection: voiceBinding) {
                        Text("System default").tag(Optional<String>.none)
                        ForEach(SpeechService.preferredVoices(), id: \.identifier) { voice in
                            Text(voice.name).tag(Optional(voice.identifier))
                        }
                    }
                    .labelsHidden()
                }

                section("Sources") {
                    Toggle("Unsplash B-roll", isOn: $state.useUnsplash)
                    if state.useUnsplash && !state.unsplashConfigured {
                        Button("Add Unsplash key in Settings") { state.showSettings = true }
                            .buttonStyle(GhostButtonStyle())
                    }
                    Toggle("Use local AI if available", isOn: $state.useLocalAI)
                    DropZone()
                    if let voice = state.voiceoverURL {
                        Text("VO: \(voice.lastPathComponent)")
                            .font(.system(size: 11))
                            .foregroundStyle(RFTheme.muted)
                    }
                    if !state.footageURLs.isEmpty {
                        Text("\(state.footageURLs.count) local files")
                            .font(.system(size: 11))
                            .foregroundStyle(RFTheme.muted)
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

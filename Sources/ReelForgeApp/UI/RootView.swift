import SwiftUI

struct RootView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ZStack {
            RFTheme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                TopBar()
                Divider().overlay(RFTheme.border)
                HStack(spacing: 0) {
                    PresetGallery()
                        .frame(width: 292)
                    Divider().overlay(RFTheme.border)
                    PreviewPane()
                    Divider().overlay(RFTheme.border)
                    Inspector()
                        .frame(width: 332)
                }
            }
        }
        .foregroundStyle(RFTheme.text)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $state.showSettings) {
            SettingsView()
                .environmentObject(state)
        }
        .onAppear { state.refreshStatus() }
    }
}

struct TopBar: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 10) {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [RFTheme.accent, RFTheme.gold],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 18, height: 18)
                Text("ReelForge")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Text("AUTO")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(RFTheme.accent.opacity(0.18), in: Capsule())
                    .foregroundStyle(RFTheme.accent)
            }
            Spacer()
            statusChips
            Button("New") { state.newProject() }
                .buttonStyle(GhostButtonStyle())
            Button("Settings") { state.showSettings = true }
                .buttonStyle(GhostButtonStyle())
            Button("Export") { state.revealExport() }
                .buttonStyle(GhostButtonStyle())
                .disabled(state.exportURL == nil)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
    }

    private var statusChips: some View {
        HStack(spacing: 8) {
            chip(state.localStatus.comfyUI ? "ComfyUI" : "Comfy off", on: state.localStatus.comfyUI)
            chip(state.localStatus.ollama ? "Ollama" : "LLM off", on: state.localStatus.ollama)
            chip(state.unsplashConfigured ? "Unsplash" : "No Unsplash", on: state.unsplashConfigured)
            if state.localStatus.aceStep {
                chip("ACE-Step", on: true)
            }
        }
    }

    private func chip(_ title: String, on: Bool) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((on ? Color.green : RFTheme.muted).opacity(on ? 0.18 : 0.12), in: Capsule())
            .foregroundStyle(on ? Color.green.opacity(0.9) : RFTheme.muted)
    }
}

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(RFTheme.elevated.opacity(configuration.isPressed ? 0.7 : 1), in: Capsule())
            .overlay(Capsule().stroke(RFTheme.border, lineWidth: 1))
    }
}

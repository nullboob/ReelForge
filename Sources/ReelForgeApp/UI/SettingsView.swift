import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @State private var key: String = ""
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Settings")
                    .font(.system(size: 20, weight: .semibold))
                Spacer()
                Button("Done") { state.showSettings = false }
                    .buttonStyle(GhostButtonStyle())
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Unsplash access key")
                    .font(.system(size: 12, weight: .medium))
                SecureField("Paste a production access key", text: $key)
                    .textFieldStyle(.roundedBorder)
                Text("Stored in Keychain. You can also set REELFORGE_UNSPLASH_ACCESS_KEY. Without a key the pipeline still exports using styled cards.")
                    .font(.system(size: 11))
                    .foregroundStyle(RFTheme.muted)
                HStack {
                    Button("Save key") {
                        KeychainStore.set(key, account: KeychainStore.unsplashAccount)
                        state.refreshStatus()
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

            VStack(alignment: .leading, spacing: 8) {
                Text("Local services")
                    .font(.system(size: 12, weight: .medium))
                statusRow("Ollama", state.localStatus.ollama, state.localStatus.ollamaModel ?? "http://127.0.0.1:11434")
                statusRow("Automatic1111 / Comfy-style image", state.localStatus.anyImage, "http://127.0.0.1:7860")
                statusRow("Local whisper", state.localStatus.whisper, "http://127.0.0.1:9000")
                Button("Re-scan") { state.refreshStatus() }
                    .buttonStyle(GhostButtonStyle())
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Attribution")
                    .font(.system(size: 12, weight: .medium))
                Text("Unsplash photographer names are stored on the project JSON. They are not burned into the video.")
                    .font(.system(size: 11))
                    .foregroundStyle(RFTheme.muted)
            }

            Spacer()
        }
        .padding(28)
        .frame(width: 520, height: 520)
        .background(RFTheme.bg)
        .onAppear {
            key = KeychainStore.string(account: KeychainStore.unsplashAccount) ?? ""
            state.refreshStatus()
        }
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

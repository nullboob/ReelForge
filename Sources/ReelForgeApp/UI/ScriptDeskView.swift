import SwiftUI

struct ScriptDeskView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Script desk")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("YouTube reviews inauthentic firehose at the channel. Accept is required.")
                    .font(.system(size: 10))
                    .foregroundStyle(RFTheme.muted)
            }

            labeled("Hook — first 3s promise") {
                TextField("Pattern-interrupt claim", text: $state.deskHook)
                    .textFieldStyle(.roundedBorder)
            }

            Text("Beats")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(RFTheme.muted)
            ForEach($state.deskBody) { $line in
                TextField("Body beat", text: $line.text)
                    .textFieldStyle(.roundedBorder)
            }
            Button("Add beat") { state.addDeskBodyLine() }
                .buttonStyle(GhostButtonStyle())

            labeled("CTA") {
                TextField("Subscribe / next step", text: $state.deskCTA)
                    .textFieldStyle(.roundedBorder)
            }

            if !state.project.captions.isEmpty {
                Text("Captions (edit before export)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(RFTheme.muted)
                ForEach(Array(state.project.captions.enumerated()), id: \.element.id) { index, _ in
                    TextField("Caption", text: captionBinding(index))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                }
            }

            if let beats = state.project.storyboard?.beats {
                Text(beats.prefix(6).map { "\($0.role.label): \(Int($0.duration * 10) / 10)s" }.joined(separator: "  ·  "))
                    .font(.system(size: 10))
                    .foregroundStyle(RFTheme.gold)
            }

            Button("Accept script") { state.acceptScript() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(state.deskHook.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.isGenerating)
        }
        .padding(14)
        .rfCard(radius: 14)
    }

    private func captionBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: {
                guard state.project.captions.indices.contains(index) else { return "" }
                return state.project.captions[index].text
            },
            set: { newValue in
                guard state.project.captions.indices.contains(index) else { return }
                state.project.captions[index].text = newValue
            }
        )
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

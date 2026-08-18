import AVKit
import SwiftUI

struct PreviewPane: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.black.opacity(0.55))
                if let player = state.player {
                    PlayerView(player: player)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .padding(14)
                } else {
                    emptyState
                }
            }
            .aspectRatio(previewRatio, contentMode: .fit)
            .frame(maxHeight: 560)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(RFTheme.border, lineWidth: 1)
            )

            GenerationProgressView()

            if let url = state.exportURL {
                HStack(spacing: 10) {
                    Button("Play") { state.attachPlayer(url) }
                        .buttonStyle(PrimaryButtonStyle())
                    Button("Reveal in Finder") { state.revealExport() }
                        .buttonStyle(GhostButtonStyle())
                    Spacer()
                    Text(url.lastPathComponent)
                        .font(.system(size: 11))
                        .foregroundStyle(RFTheme.muted)
                        .lineLimit(1)
                }
            }

            PublishPackView()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var previewRatio: CGFloat {
        let size = state.resolvedAspect.pixelSize
        return CGFloat(size.width) / CGFloat(size.height)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles.tv")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(RFTheme.gold)
            Text("Type a topic, pick a preset, generate")
                .font(.system(size: 18, weight: .semibold))
            Text("The director writes a script, times the beats, speaks the line, burns captions, grades the picture, and exports an MP4. You do not cut a single clip.")
                .font(.system(size: 12))
                .foregroundStyle(RFTheme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .padding(30)
    }
}

struct PlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .inline
        view.showsFullScreenToggleButton = true
        view.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}

import SwiftUI
import UniformTypeIdentifiers

struct DropZone: View {
    @EnvironmentObject private var state: AppState
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 18, weight: .medium))
            Text("Drop footage or a voiceover")
                .font(.system(size: 12, weight: .medium))
            Text("MP4, MOV, photos, WAV, M4A — or a folder")
                .font(.system(size: 10))
                .foregroundStyle(RFTheme.muted)
            Button("Browse…") { state.pickMedia() }
                .buttonStyle(GhostButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(hovering ? RFTheme.elevated : RFTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .foregroundStyle(hovering ? RFTheme.gold : RFTheme.border)
        )
        .onDrop(of: [.fileURL], isTargeted: $hovering) { providers in
            Task { await ingest(providers) }
            return true
        }
    }

    private func ingest(_ providers: [NSItemProvider]) async {
        var urls: [URL] = []
        for provider in providers {
            if let url = await loadURL(provider) {
                urls.append(url)
            }
        }
        await MainActor.run {
            state.addDroppedURLs(urls)
        }
    }

    private func loadURL(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                } else if let url = item as? URL {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

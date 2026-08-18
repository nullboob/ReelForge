import AppKit
import SwiftUI

struct PublishPackView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Group {
            if let pack = state.publishPack {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Publish pack")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Button("Copy title") { copy(pack.title) }
                            .buttonStyle(GhostButtonStyle())
                        Button("Copy description") { copy(pack.description) }
                            .buttonStyle(GhostButtonStyle())
                        Button("Upload") {}
                            .buttonStyle(GhostButtonStyle())
                            .disabled(true)
                            .help("YouTube Data API OAuth is not wired. Coming soon.")
                    }
                    Text(pack.title)
                        .font(.system(size: 16, weight: .semibold))
                    Text(pack.description)
                        .font(.system(size: 11))
                        .foregroundStyle(RFTheme.muted)
                        .lineLimit(6)
                    Text(pack.tags.joined(separator: " · "))
                        .font(.system(size: 10))
                        .foregroundStyle(RFTheme.gold)
                    if !pack.chapters.isEmpty {
                        Text(pack.chapters.prefix(6).map { "\($0.timestamp) \($0.title)" }.joined(separator: "  ·  "))
                            .font(.system(size: 10))
                            .foregroundStyle(RFTheme.muted)
                            .lineLimit(2)
                    }
                    HStack {
                        Text(pack.suggestedFilename)
                            .font(.system(size: 10))
                            .foregroundStyle(RFTheme.muted)
                        if pack.thumbnailPath != nil {
                            Text("Thumbnail saved next to the MP4")
                                .font(.system(size: 10))
                                .foregroundStyle(RFTheme.gold)
                        }
                        if pack.srtPath != nil {
                            Text("SRT exported")
                                .font(.system(size: 10))
                                .foregroundStyle(RFTheme.gold)
                        }
                    }
                }
                .padding(14)
                .rfCard(radius: 14)
            }
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

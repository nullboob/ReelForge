import SwiftUI

struct PresetGallery: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Presets")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(RFTheme.muted)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(RFTheme.muted)
                TextField("Search styles", text: $state.search)
                    .textFieldStyle(.plain)
            }
            .padding(9)
            .background(RFTheme.elevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(RFTheme.border, lineWidth: 1)
            )

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(state.filteredPresets) { preset in
                        PresetCard(preset: preset, selected: state.selectedPreset?.id == preset.id)
                            .onTapGesture { state.selectedPreset = preset }
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .padding(18)
        .background(RFTheme.bg)
    }
}

struct PresetCard: View {
    let preset: Preset
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(gradient)
                .frame(height: 72)
                .overlay(alignment: .bottomLeading) {
                    HStack(spacing: 6) {
                        badge(preset.aspect.rawValue)
                        badge("\(preset.durationSec)s")
                    }
                    .padding(8)
                }
            Text(preset.name)
                .font(.system(size: 14, weight: .semibold))
            Text(preset.tagline)
                .font(.system(size: 11))
                .foregroundStyle(RFTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(RFTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(selected ? RFTheme.accent : RFTheme.border, lineWidth: selected ? 2 : 1)
        )
        .scaleEffect(selected ? 1.01 : 1)
        .shadow(color: selected ? RFTheme.accent.opacity(0.18) : .clear, radius: 12)
        .animation(.easeOut(duration: 0.18), value: selected)
    }

    private var gradient: LinearGradient {
        let colors = preset.coverGradient.map { Color(hex: $0) }
        return LinearGradient(colors: colors.isEmpty ? [RFTheme.accent, .black] : colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.black.opacity(0.35), in: Capsule())
    }
}

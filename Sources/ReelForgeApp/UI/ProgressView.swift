import SwiftUI

struct GenerationProgressView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(state.progress.detail.isEmpty ? PipelineProgress.idle.detail : state.progress.detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(state.progress.isFailed ? RFTheme.accent : RFTheme.text)
                Spacer()
                if state.isGenerating {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(RFTheme.elevated)
                    Capsule()
                        .fill(LinearGradient(colors: [RFTheme.accent, RFTheme.gold], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * state.progress.fraction)
                }
            }
            .frame(height: 4)

            HStack(spacing: 8) {
                ForEach(PipelineStep.allCases, id: \.self) { step in
                    stepDot(step)
                }
            }
        }
        .padding(14)
        .rfCard(radius: 14)
    }

    private func stepDot(_ step: PipelineStep) -> some View {
        let done = state.progress.isDone(step)
        let current = state.progress.current == step
        return VStack(spacing: 4) {
            Image(systemName: done ? "checkmark.circle.fill" : current ? "record.circle" : "circle")
                .foregroundStyle(done ? Color.green : current ? RFTheme.gold : RFTheme.muted)
            Text(step.title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(done || current ? RFTheme.text : RFTheme.muted)
        }
        .frame(maxWidth: .infinity)
    }
}

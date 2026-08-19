import Foundation

struct ScriptService {
    func write(
        topic: String,
        preset: Preset,
        preferOllama: Bool,
        durationSec: Int,
        channelType: ChannelType
    ) async -> (GeneratedScript, [String]) {
        var warnings: [String] = []
        let trimmed = topic.trimmingCharacters(in: .whitespacesAndNewlines)

        if ScriptWriter.looksLikeFullScript(trimmed) {
            return (ScriptWriter.parseUserScript(trimmed), warnings)
        }

        if preferOllama {
            let status = await LocalAIClient.shared.probe()
            if let model = status.ollamaModel,
               let raw = await LocalAIClient.shared.generateScript(
                topic: trimmed,
                preset: preset,
                model: model,
                durationSec: durationSec
               ) {
                return (ScriptWriter.parseModelOutput(raw, fallbackTopic: trimmed, presetID: preset.id), warnings)
            }
            warnings.append("Ollama was off or busy — used the built-in writer.")
        }

        return (
            ScriptWriter.write(
                topic: trimmed,
                presetID: preset.id,
                durationSec: durationSec,
                channelType: channelType
            ),
            warnings
        )
    }
}

import Foundation

struct CaptionService {
    func cues(
        script: GeneratedScript,
        storyboard: Storyboard,
        preset: Preset,
        voiceURL: URL?,
        allowLocalWhisper: Bool
    ) async -> (cues: [CaptionCue], warning: String?) {
        if allowLocalWhisper, let voiceURL {
            if let whispered = await transcribeLocalWhisper(voiceURL) {
                let aligned = CaptionSplitter.align(
                    text: whispered,
                    duration: storyboard.duration,
                    maxWordsPerCard: preset.captionStyle.maxWordsPerCard
                )
                if !aligned.isEmpty {
                    return (aligned, nil)
                }
            }
        }
        let cues = CaptionSplitter.cues(
            from: script,
            duration: storyboard.duration,
            maxWordsPerCard: preset.captionStyle.maxWordsPerCard,
            storyboard: storyboard
        )
        return (cues, nil)
    }

    /// Optional faster-whisper / whisper.cpp HTTP. Duration alignment is the guaranteed path.
    private func transcribeLocalWhisper(_ url: URL) async -> String? {
        guard let endpoint = URL(string: "http://127.0.0.1:9000/asr") else { return nil }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        let boundary = "ReelForge\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        guard let fileData = try? Data(contentsOf: url) else { return nil }
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"audio_file\"; filename=\"voice.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200
        else { return nil }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = json["text"] as? String, !text.isEmpty {
            return text
        }
        return String(data: data, encoding: .utf8)
    }
}

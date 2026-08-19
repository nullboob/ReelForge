import Foundation

struct WhisperTranscript {
    var text: String
    var words: [WordTiming]
}

struct CaptionService {
    func cues(
        script: GeneratedScript,
        storyboard: Storyboard,
        preset: Preset,
        voiceURL: URL?,
        allowLocalWhisper: Bool,
        captionStyleID: String? = nil,
        existing: [CaptionCue] = []
    ) async -> (cues: [CaptionCue], warning: String?) {
        let requested = CaptionCatalog.look(id: captionStyleID).maxWords
        let maxWords = CaptionSafeArea.maxWords(forPresetID: preset.id, requested: requested)
        var cues = existing.isEmpty
            ? CaptionSplitter.cues(
                from: script,
                duration: storyboard.duration,
                maxWordsPerCard: maxWords,
                storyboard: storyboard
            )
            : existing
        if allowLocalWhisper, let voiceURL {
            if let whisper = await transcribeLocalWhisper(voiceURL), !whisper.words.isEmpty {
                cues = CaptionSplitter.forceAlign(cues, timed: whisper.words)
            }
        }
        return (cues, nil)
    }

    /// Optional faster-whisper / whisper.cpp HTTP. Script text stays canonical; only word times are stolen.
    private func transcribeLocalWhisper(_ url: URL) async -> WhisperTranscript? {
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
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return parseWhisper(json)
        }
        return nil
    }

    static func parseWhisper(_ json: [String: Any]) -> WhisperTranscript {
        var words: [WordTiming] = []
        if let top = json["words"] as? [[String: Any]] {
            words.append(contentsOf: top.compactMap(wordTiming))
        }
        if let segments = json["segments"] as? [[String: Any]] {
            for segment in segments {
                if let segmentWords = segment["words"] as? [[String: Any]] {
                    words.append(contentsOf: segmentWords.compactMap(wordTiming))
                }
            }
        }
        let text = (json["text"] as? String) ?? ""
        return WhisperTranscript(text: text, words: words)
    }

    private static func wordTiming(_ item: [String: Any]) -> WordTiming? {
        let token = ((item["word"] as? String) ?? (item["text"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return nil }
        let start = doubleValue(item["start"]) ?? 0
        let end = doubleValue(item["end"])
        let duration = doubleValue(item["duration"]) ?? max(0.04, (end ?? start) - start)
        return WordTiming(word: token, start: start, duration: max(0.04, duration))
    }

    private static func doubleValue(_ raw: Any?) -> Double? {
        if let value = raw as? Double { return value }
        if let value = raw as? Int { return Double(value) }
        if let value = raw as? String { return Double(value) }
        return nil
    }
}

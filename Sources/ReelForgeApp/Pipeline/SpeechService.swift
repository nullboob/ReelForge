import AVFoundation
import Foundation

enum SpeechServiceError: Error {
    case emptyUtterance
    case writeFailed
    case noKokoroClassVoice
}

struct VoiceChoice: Identifiable, Hashable {
    var id: String
    var name: String
    var engine: String
}

struct SpeechService {
    static func allVoices() -> [VoiceChoice] {
        [
            VoiceChoice(id: "kokoro:af_bella", name: "Kokoro · Bella", engine: "Kokoro"),
            VoiceChoice(id: "kokoro:af_sarah", name: "Kokoro · Sarah", engine: "Kokoro"),
            VoiceChoice(id: "kokoro:am_adam", name: "Kokoro · Adam", engine: "Kokoro"),
            VoiceChoice(id: "kokoro:am_michael", name: "Kokoro · Michael", engine: "Kokoro"),
            VoiceChoice(id: "kokoro:bf_emma", name: "Kokoro · Emma", engine: "Kokoro"),
            VoiceChoice(id: "kokoro:af_nicole", name: "Kokoro · Nicole", engine: "Kokoro"),
            VoiceChoice(id: "kokoro:am_fenrir", name: "Kokoro · Fenrir", engine: "Kokoro")
        ]
    }

    static func edgeTTSCLI() -> String? {
        let candidates = ["/opt/homebrew/bin/edge-tts", "/usr/local/bin/edge-tts", "/usr/bin/edge-tts"]
        if let hit = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return hit
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = ["edge-tts"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        try? task.run()
        task.waitUntilExit()
        let path = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let path, FileManager.default.isExecutableFile(atPath: path) { return path }
        return nil
    }

    func synthesize(
        text: String,
        voiceIdentifier: String?,
        speed: Double,
        to url: URL
    ) async throws -> (duration: TimeInterval, engine: String) {
        let wantsKokoro = voiceIdentifier == nil || voiceIdentifier?.hasPrefix("kokoro:") == true
        if wantsKokoro {
            let voice = voiceIdentifier?.hasPrefix("kokoro:") == true
                ? String(voiceIdentifier!.dropFirst(7))
                : "af_bella"
            if let duration = await kokoro(text: text, voice: voice, speed: speed, to: url) {
                return (duration, "Kokoro")
            }
        }
        if let duration = await edgeTTS(text: text, to: url) {
            return (duration, "edge-tts-cli")
        }
        if let duration = await basicVoice(text: text, to: url) {
            return (duration, "basic voice")
        }
        throw SpeechServiceError.noKokoroClassVoice
    }

    static func defaultVoice() -> VoiceChoice? {
        allVoices().first
    }

    private func kokoro(text: String, voice: String, speed: Double, to url: URL) async -> TimeInterval? {
        for raw in ["http://127.0.0.1:8880/v1/audio/speech", "http://127.0.0.1:8880/audio/speech"] {
            guard let endpoint = URL(string: raw) else { continue }
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 60
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: [
                "model": "kokoro",
                "input": text,
                "voice": voice,
                "response_format": "wav",
                "speed": max(0.7, min(1.4, speed))
            ])
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  data.count > 200
            else { continue }
            try? data.write(to: url)
            if FileManager.default.fileExists(atPath: url.path) {
                return await durationOfAudio(at: url) ?? estimateDuration(text: text)
            }
        }
        return nil
    }

    private func edgeTTS(text: String, to url: URL) async -> TimeInterval? {
        guard let binary = Self.edgeTTSCLI() else { return nil }
        let tmp = url.deletingPathExtension().appendingPathExtension("edge.mp3")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: binary)
        task.arguments = ["--voice", "en-US-JennyNeural", "--text", text, "--write-media", tmp.path]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return nil
        }
        guard task.terminationStatus == 0, FileManager.default.fileExists(atPath: tmp.path) else { return nil }
        guard let ffmpeg = FFmpegFallback.resolve() else { return nil }
        let convert = Process()
        convert.executableURL = URL(fileURLWithPath: ffmpeg)
        convert.arguments = ["-hide_banner", "-y", "-i", tmp.path, "-ac", "1", "-ar", "44100", url.path]
        convert.standardOutput = Pipe()
        convert.standardError = Pipe()
        try? convert.run()
        convert.waitUntilExit()
        try? FileManager.default.removeItem(at: tmp)
        if convert.terminationStatus == 0, FileManager.default.fileExists(atPath: url.path) {
            return await durationOfAudio(at: url) ?? estimateDuration(text: text)
        }
        return nil
    }

    func durationOfAudio(at url: URL) async -> TimeInterval? {
        let asset = AVURLAsset(url: url)
        if #available(macOS 13.0, *) {
            return try? await asset.load(.duration).seconds
        }
        return asset.duration.seconds
    }

    func estimateDuration(text: String) -> TimeInterval {
        let words = text.split { $0.isWhitespace || $0.isNewline }.count
        return max(4, Double(words) / 2.35)
    }

    private func basicVoice(text: String, to url: URL) async -> TimeInterval? {
        let say = "/usr/bin/say"
        guard FileManager.default.isExecutableFile(atPath: say) else { return nil }
        let aiff = url.deletingPathExtension().appendingPathExtension("aiff")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: say)
        task.arguments = ["-o", aiff.path, String(text.prefix(800))]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        do { try task.run(); task.waitUntilExit() } catch { return nil }
        guard task.terminationStatus == 0, FileManager.default.fileExists(atPath: aiff.path) else { return nil }
        guard let ffmpeg = FFmpegFallback.resolve() else {
            try? FileManager.default.copyItem(at: aiff, to: url)
            return FileManager.default.fileExists(atPath: url.path) ? estimateDuration(text: text) : nil
        }
        let convert = Process()
        convert.executableURL = URL(fileURLWithPath: ffmpeg)
        convert.arguments = ["-hide_banner", "-y", "-i", aiff.path, "-ac", "1", "-ar", "44100", url.path]
        convert.standardOutput = Pipe()
        convert.standardError = Pipe()
        try? convert.run()
        convert.waitUntilExit()
        try? FileManager.default.removeItem(at: aiff)
        if convert.terminationStatus == 0, FileManager.default.fileExists(atPath: url.path) {
            return await durationOfAudio(at: url) ?? estimateDuration(text: text)
        }
        return nil
    }
}

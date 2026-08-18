import AVFoundation
import Foundation

enum SpeechServiceError: Error {
    case emptyUtterance
    case writeFailed
}

struct VoiceChoice: Identifiable, Hashable {
    var id: String
    var name: String
    var engine: String
}

struct SpeechService {
    static func preferredVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted { lhs, rhs in
                if lhs.quality != rhs.quality { return lhs.quality.rawValue > rhs.quality.rawValue }
                return lhs.name < rhs.name
            }
    }

    static func defaultVoice() -> AVSpeechSynthesisVoice? {
        if let samantha = preferredVoices().first(where: { $0.identifier.contains("Samantha") }) {
            return samantha
        }
        return preferredVoices().first ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    static func allVoices() -> [VoiceChoice] {
        var items: [VoiceChoice] = [
            VoiceChoice(id: "kokoro:af_bella", name: "Kokoro · Bella", engine: "Kokoro"),
            VoiceChoice(id: "kokoro:af_sarah", name: "Kokoro · Sarah", engine: "Kokoro"),
            VoiceChoice(id: "kokoro:am_adam", name: "Kokoro · Adam", engine: "Kokoro"),
            VoiceChoice(id: "kokoro:am_michael", name: "Kokoro · Michael", engine: "Kokoro"),
            VoiceChoice(id: "kokoro:bf_emma", name: "Kokoro · Emma", engine: "Kokoro"),
            VoiceChoice(id: "kokoro:af_nicole", name: "Kokoro · Nicole", engine: "Kokoro"),
            VoiceChoice(id: "kokoro:am_fenrir", name: "Kokoro · Fenrir", engine: "Kokoro")
        ]
        items.append(contentsOf: preferredVoices().prefix(10).map {
            VoiceChoice(id: $0.identifier, name: "Mac · \($0.name)", engine: "AVSpeech")
        })
        return items
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
        let appleID = voiceIdentifier?.hasPrefix("kokoro:") == true ? nil : voiceIdentifier
        let duration = try await synthesizeApple(text: text, voiceIdentifier: appleID, speed: speed, to: url)
        return (duration, "AVSpeech")
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

    func synthesizeApple(text: String, voiceIdentifier: String?, speed: Double, to url: URL) async throws -> TimeInterval {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw SpeechServiceError.emptyUtterance }

        let utterance = AVSpeechUtterance(string: cleaned)
        if let voiceIdentifier, let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            utterance.voice = voice
        } else {
            utterance.voice = Self.defaultVoice()
        }
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.94 * Float(max(0.7, min(1.4, speed)))
        utterance.pitchMultiplier = 0.98
        utterance.volume = 1

        let synthesizer = AVSpeechSynthesizer()
        return try await withCheckedThrowingContinuation { continuation in
            let collector = SpeechCollector(url: url, continuation: continuation)
            collector.retainSynthesizer(synthesizer)
            synthesizer.write(utterance) { buffer in
                collector.consume(buffer)
            }
        }
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
}

private final class SpeechCollector: @unchecked Sendable {
    private let url: URL
    private var buffers: [AVAudioPCMBuffer] = []
    private var finished = false
    private var synthesizer: AVSpeechSynthesizer?
    private let continuation: CheckedContinuation<TimeInterval, Error>
    private let lock = NSLock()

    init(url: URL, continuation: CheckedContinuation<TimeInterval, Error>) {
        self.url = url
        self.continuation = continuation
    }

    func retainSynthesizer(_ synthesizer: AVSpeechSynthesizer) {
        self.synthesizer = synthesizer
    }

    func consume(_ buffer: AVAudioBuffer) {
        lock.lock()
        defer { lock.unlock() }
        if let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 {
            if let copy = copyBuffer(pcm) {
                buffers.append(copy)
            }
            return
        }
        guard !finished else { return }
        finished = true
        do {
            let duration = try writeWAV(buffers: buffers, to: url)
            continuation.resume(returning: duration)
        } catch {
            continuation.resume(throwing: error)
        }
        synthesizer = nil
    }

    private func copyBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else { return nil }
        copy.frameLength = buffer.frameLength
        if let src = buffer.floatChannelData, let dst = copy.floatChannelData {
            for channel in 0..<Int(buffer.format.channelCount) {
                dst[channel].update(from: src[channel], count: Int(buffer.frameLength))
            }
        } else if let src = buffer.int16ChannelData, let dst = copy.int16ChannelData {
            for channel in 0..<Int(buffer.format.channelCount) {
                dst[channel].update(from: src[channel], count: Int(buffer.frameLength))
            }
        }
        return copy
    }

    private func writeWAV(buffers: [AVAudioPCMBuffer], to url: URL) throws -> TimeInterval {
        guard let first = buffers.first else { throw SpeechServiceError.writeFailed }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        let file = try AVAudioFile(forWriting: url, settings: first.format.settings)
        var frames: AVAudioFramePosition = 0
        for buffer in buffers {
            try file.write(from: buffer)
            frames += Int64(buffer.frameLength)
        }
        let duration = Double(frames) / first.format.sampleRate
        return max(0.4, duration)
    }
}

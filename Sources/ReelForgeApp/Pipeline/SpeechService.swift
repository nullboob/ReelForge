import AVFoundation
import Foundation

enum SpeechServiceError: Error {
    case emptyUtterance
    case writeFailed
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

    func synthesize(text: String, voiceIdentifier: String?, to url: URL) async throws -> TimeInterval {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw SpeechServiceError.emptyUtterance }

        let utterance = AVSpeechUtterance(string: cleaned)
        if let voiceIdentifier, let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            utterance.voice = voice
        } else {
            utterance.voice = Self.defaultVoice()
        }
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.94
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

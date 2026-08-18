import AVFoundation
import Foundation

enum VideoExporter {
    static func export(
        built: BuiltComposition,
        to outputURL: URL,
        fallbackClips: [URL],
        fallbackAudio: [URL]
    ) async throws {
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        do {
            try await exportSession(built: built, to: outputURL)
        } catch {
            if FFmpegFallback.isAvailable {
                try FFmpegFallback.export(clips: fallbackClips, audio: fallbackAudio, to: outputURL)
            } else {
                throw error
            }
        }
    }

    private static func exportSession(built: BuiltComposition, to outputURL: URL) async throws {
        guard let session = AVAssetExportSession(asset: built.composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw ExportError.exportFailed("AVAssetExportSession is unavailable.")
        }
        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.videoComposition = built.videoComposition
        session.audioMix = built.audioMix
        session.shouldOptimizeForNetworkUse = true
        session.timeRange = CMTimeRange(start: .zero, duration: built.duration)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously {
                continuation.resume()
            }
        }

        switch session.status {
        case .completed:
            return
        case .cancelled:
            throw ExportError.cancelled
        default:
            throw ExportError.exportFailed(session.error?.localizedDescription ?? "Export failed.")
        }
    }
}

enum FFmpegFallback {
    static var isAvailable: Bool {
        resolve() != nil
    }

    static func resolve() -> String? {
        let candidates = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
        if let hit = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return hit
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = ["ffmpeg"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        try? task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let path, FileManager.default.isExecutableFile(atPath: path) { return path }
        return nil
    }

    static func export(clips: [URL], audio: [URL], to output: URL) throws {
        guard let ffmpeg = resolve(), !clips.isEmpty else {
            throw ExportError.exportFailed("ffmpeg fallback was requested but is not available.")
        }
        let list = output.deletingLastPathComponent().appendingPathComponent("ffmpeg-concat.txt")
        let lines = clips.map { "file '\($0.path.replacingOccurrences(of: "'", with: "'\\''"))'" }.joined(separator: "\n")
        try lines.write(to: list, atomically: true, encoding: .utf8)

        var args = ["-y", "-f", "concat", "-safe", "0", "-i", list.path]
        for url in audio {
            args += ["-i", url.path]
        }
        if audio.isEmpty {
            args += ["-c:v", "libx264", "-pix_fmt", "yuv420p", output.path]
        } else {
            var filter = ""
            if audio.count == 1 {
                filter = "[1:a]volume=1.0[a]"
            } else {
                filter = "[1:a]volume=1.0[v0];[2:a]volume=0.16[v1];[v0][v1]amix=inputs=2:duration=first:dropout_transition=2[a]"
            }
            args += ["-filter_complex", filter, "-map", "0:v", "-map", "[a]", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest", output.path]
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: ffmpeg)
        task.arguments = args
        let err = Pipe()
        task.standardError = err
        task.standardOutput = Pipe()
        try task.run()
        task.waitUntilExit()
        if task.terminationStatus != 0 || !FileManager.default.fileExists(atPath: output.path) {
            let message = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "ffmpeg failed"
            throw ExportError.exportFailed(message)
        }
    }
}

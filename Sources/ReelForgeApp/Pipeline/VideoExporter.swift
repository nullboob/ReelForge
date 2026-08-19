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

    static func listedEncoders() -> Set<String> {
        guard let ffmpeg = resolve() else { return ["libx264"] }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: ffmpeg)
        task.arguments = ["-hide_banner", "-encoders"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        try? task.run()
        task.waitUntilExit()
        let blob = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        var found = Set(EditEncoder.whitelist.filter { blob.contains($0) })
        found.insert("libx264")
        return found
    }

    static func pickEncoder() -> String {
        let listed = listedEncoders()
        return EditEncoder.whitelist.first { listed.contains($0) } ?? "libx264"
    }

    static func videoArgs(codec: String? = nil) -> [String] {
        let name = codec ?? pickEncoder()
        var args = ["-c:v", name, "-pix_fmt", "yuv420p", "-movflags", "+faststart"]
        if name == "libx264" {
            args += ["-crf", "18", "-preset", "veryfast"]
        } else if name == "h264_nvenc" {
            args += ["-preset", "p4", "-rc", "vbr", "-cq", "19"]
        } else if name == "h264_videotoolbox" {
            args += ["-q:v", "65"]
        }
        return args
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
            args += videoArgs() + [output.path]
        } else if audio.count == 1 {
            args += ["-filter_complex", "[1:a]aformat=sample_fmts=fltp:channel_layouts=stereo[a]", "-map", "0:v", "-map", "[a]"]
            args += videoArgs() + ["-c:a", "aac", "-shortest", output.path]
        } else {
            let gap = String(format: "%.4f", pow(10.0, -8.0 / 20.0))
            let filter = "[1:a]aformat=sample_fmts=fltp:channel_layouts=stereo[vo];[2:a]aformat=sample_fmts=fltp:channel_layouts=stereo,volume=\(gap)[bg];[bg][vo]sidechaincompress=threshold=0.02:ratio=8:attack=12:release=220:makeup=1[ducked];[vo][ducked]amix=inputs=2:duration=first:normalize=0[a]"
            args += ["-filter_complex", filter, "-map", "0:v", "-map", "[a]"]
            args += videoArgs() + ["-c:a", "aac", "-shortest", output.path]
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

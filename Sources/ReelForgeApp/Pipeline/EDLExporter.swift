import Foundation

enum EDLExporter {
    static func export(
        _ edl: EditList,
        to dest: URL,
        workDir: URL,
        fontsDir: String,
        burnCaptions: Bool
    ) throws {
        guard let ffmpeg = FFmpegFallback.resolve() else {
            throw ExportError.exportFailed("ffmpeg is not available for one-encode.")
        }
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        let graph = edl.filterComplex(fontsDir: fontsDir, burnCaptions: burnCaptions)
        if graph.contains("fade=t=in") && graph.lowercased().contains("black") {
            throw ExportError.exportFailed("Hook must never fade from black.")
        }
        var args = ["-hide_banner", "-y"]
        for clip in edl.clips {
            let source = resolve(path: clip.source, workDir: workDir)
            guard FileManager.default.fileExists(atPath: source.path) else {
                throw ExportError.exportFailed("EDL source missing: \(clip.source)")
            }
            let dur = String(format: "%.3f", max(0.4, clip.duration))
            if clip.kind == "image" || clip.kind == "card" {
                args += ["-loop", "1", "-t", dur, "-i", source.path]
            } else {
                args += ["-stream_loop", "-1", "-t", dur, "-i", source.path]
            }
        }
        args += ["-i", resolve(path: edl.voice.path, workDir: workDir).path]
        args += ["-i", resolve(path: edl.music.path, workDir: workDir).path]
        args += [
            "-filter_complex", graph,
            "-map", "[vout]",
            "-map", "[a]"
        ]
        args += FFmpegFallback.videoArgs()
        args += ["-r", "\(edl.fps)", "-c:a", "aac", "-b:a", "192k", "-shortest", dest.path]

        let task = Process()
        task.executableURL = URL(fileURLWithPath: ffmpeg)
        task.currentDirectoryURL = workDir
        task.arguments = args
        let err = Pipe()
        task.standardError = err
        task.standardOutput = Pipe()
        try task.run()
        task.waitUntilExit()
        if task.terminationStatus != 0 || !FileManager.default.fileExists(atPath: dest.path) {
            let message = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "ffmpeg failed"
            throw ExportError.exportFailed(message)
        }
    }

    private static func resolve(path: String, workDir: URL) -> URL {
        let asIs = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: asIs.path) { return asIs }
        return workDir.appendingPathComponent((path as NSString).lastPathComponent)
    }
}

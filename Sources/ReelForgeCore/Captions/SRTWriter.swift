import Foundation

public enum SRTWriter {
    public static func string(from cues: [CaptionCue]) -> String {
        cues.enumerated().map { index, cue in
            """
            \(index + 1)
            \(stamp(cue.start)) --> \(stamp(cue.end))
            \(cue.text)
            """
        }.joined(separator: "\n\n") + (cues.isEmpty ? "" : "\n")
    }

    public static func write(cues: [CaptionCue], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try string(from: cues).write(to: url, atomically: true, encoding: .utf8)
    }

    public static func stamp(_ seconds: Double) -> String {
        let clamped = max(0, seconds)
        let hours = Int(clamped) / 3600
        let minutes = (Int(clamped) % 3600) / 60
        let secs = Int(clamped) % 60
        let millis = Int((clamped - floor(clamped)) * 1000)
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, secs, millis)
    }
}

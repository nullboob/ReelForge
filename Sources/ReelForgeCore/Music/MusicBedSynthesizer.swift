import Foundation

public enum MusicBedSynthesizer {
    public static let sampleRate = 44100
    public static let loopSeconds = 8.0

    public static func writeLoop(mood: MusicMood, bpm: Int, to url: URL) throws {
        let frames = Int(loopSeconds * Double(sampleRate))
        var left = [Float](repeating: 0, count: frames)
        var right = [Float](repeating: 0, count: frames)
        render(mood: mood, bpm: max(60, bpm), left: &left, right: &right)
        try WAVWriter.writeStereo(left: left, right: right, sampleRate: sampleRate, to: url)
    }

    public static func writeLoopMatchingDuration(mood: MusicMood, bpm: Int, duration: Double, to url: URL) throws {
        try writeLoop(mood: mood, bpm: bpm, to: url)
        _ = duration
    }

    public static func writeSilence(duration: Double, to url: URL) throws {
        let frames = Int(max(0.4, duration) * Double(sampleRate))
        let zeros = [Float](repeating: 0, count: frames)
        try WAVWriter.writeStereo(left: zeros, right: zeros, sampleRate: sampleRate, to: url)
    }

    private static func render(mood: MusicMood, bpm: Int, left: inout [Float], right: inout [Float]) {
        let n = left.count
        let beat = 60.0 / Double(bpm)
        switch mood {
        case .pulse:
            addKick(left: &left, right: &right, beat: beat, gain: 0.55)
            addHats(left: &left, right: &right, beat: beat / 2, gain: 0.12)
            addBass(left: &left, right: &right, hz: 55, beat: beat, gain: 0.22)
            addArp(left: &left, right: &right, notes: [196, 247, 294, 392], beat: beat / 2, gain: 0.09)
        case .cinematic:
            addPad(left: &left, right: &right, freqs: [110, 165, 220, 329.6], gain: 0.18)
            addSwell(left: &left, right: &right, hz: 55, gain: 0.12)
            addSoftPulse(left: &left, right: &right, beat: beat * 2, gain: 0.08)
        case .clean:
            addKick(left: &left, right: &right, beat: beat * 2, gain: 0.28)
            addArp(left: &left, right: &right, notes: [261.6, 329.6, 392.0, 523.3], beat: beat, gain: 0.11)
            addPad(left: &left, right: &right, freqs: [130.8, 196.0], gain: 0.08)
        case .warm:
            addPad(left: &left, right: &right, freqs: [98, 147, 196, 246.9], gain: 0.16)
            addHats(left: &left, right: &right, beat: beat, gain: 0.06)
            addBass(left: &left, right: &right, hz: 49, beat: beat * 2, gain: 0.16)
            addArp(left: &left, right: &right, notes: [196, 220, 261.6, 329.6], beat: beat, gain: 0.07)
        }
        normalize(&left, &right, ceiling: 0.86)
        fadeEdges(&left, &right, ms: 12)
        _ = n
    }

    private static func addKick(left: inout [Float], right: inout [Float], beat: Double, gain: Float) {
        let frames = left.count
        let interval = Int(beat * Double(sampleRate))
        guard interval > 0 else { return }
        var t = 0
        while t < frames {
            for i in 0..<min(Int(0.18 * Double(sampleRate)), frames - t) {
                let local = Double(i) / Double(sampleRate)
                let env = exp(-local * 18)
                let hz = 140.0 * exp(-local * 12) + 42
                let s = Float(sin(2 * Double.pi * hz * local) * env) * gain
                left[t + i] += s
                right[t + i] += s
            }
            t += interval
        }
    }

    private static func addHats(left: inout [Float], right: inout [Float], beat: Double, gain: Float) {
        let frames = left.count
        let interval = Int(beat * Double(sampleRate))
        guard interval > 0 else { return }
        var seed: UInt64 = 0xC0FFEE
        var t = interval / 2
        while t < frames {
            for i in 0..<min(Int(0.03 * Double(sampleRate)), frames - t) {
                seed = seed &* 6364136223846793005 &+ 1
                let noise = Float(Int64(seed >> 33) % 1000) / 500 - 1
                let env = exp(-Double(i) / Double(sampleRate) * 80)
                let s = noise * gain * Float(env)
                let pan: Float = (i % 2 == 0) ? 0.7 : 1.0
                left[t + i] += s * pan
                right[t + i] += s * (1.4 - pan)
            }
            t += interval
        }
    }

    private static func addBass(left: inout [Float], right: inout [Float], hz: Double, beat: Double, gain: Float) {
        let frames = left.count
        let interval = Int(beat * Double(sampleRate))
        guard interval > 0 else { return }
        var t = 0
        var step = 0
        let notes = [hz, hz * 1.125, hz, hz * 0.89]
        while t < frames {
            let note = notes[step % notes.count]
            let len = min(interval, frames - t)
            for i in 0..<len {
                let local = Double(i) / Double(sampleRate)
                let env = min(1, local / 0.01) * exp(-local * 2.2)
                let s = Float(sin(2 * Double.pi * note * local) * env) * gain
                left[t + i] += s
                right[t + i] += s
            }
            t += interval
            step += 1
        }
    }

    private static func addArp(left: inout [Float], right: inout [Float], notes: [Double], beat: Double, gain: Float) {
        let frames = left.count
        let interval = Int(beat * Double(sampleRate))
        guard interval > 0, !notes.isEmpty else { return }
        var t = 0
        var step = 0
        while t < frames {
            let note = notes[step % notes.count]
            let len = min(interval, frames - t)
            for i in 0..<len {
                let local = Double(i) / Double(sampleRate)
                let env = min(1, local / 0.005) * exp(-local * 7)
                let s = Float(sin(2 * Double.pi * note * local) * env) * gain
                let pan: Float = step % 2 == 0 ? 0.8 : 1.15
                left[t + i] += s * pan
                right[t + i] += s * (1.8 - pan)
            }
            t += interval
            step += 1
        }
    }

    private static func addPad(left: inout [Float], right: inout [Float], freqs: [Double], gain: Float) {
        let frames = left.count
        for (idx, hz) in freqs.enumerated() {
            let detune = 1 + Double(idx) * 0.003
            for i in 0..<frames {
                let t = Double(i) / Double(sampleRate)
                let lfo = 0.75 + 0.25 * sin(2 * Double.pi * 0.07 * t + Double(idx))
                let s = Float(sin(2 * Double.pi * hz * detune * t) * lfo) * gain / Float(freqs.count)
                if idx % 2 == 0 {
                    left[i] += s
                    right[i] += s * 0.85
                } else {
                    left[i] += s * 0.85
                    right[i] += s
                }
            }
        }
    }

    private static func addSwell(left: inout [Float], right: inout [Float], hz: Double, gain: Float) {
        let frames = left.count
        for i in 0..<frames {
            let t = Double(i) / Double(sampleRate)
            let env = 0.5 + 0.5 * sin(2 * Double.pi * t / loopSeconds - Double.pi / 2)
            let s = Float(sin(2 * Double.pi * hz * t) * env) * gain
            left[i] += s
            right[i] += s
        }
    }

    private static func addSoftPulse(left: inout [Float], right: inout [Float], beat: Double, gain: Float) {
        let frames = left.count
        let interval = Int(beat * Double(sampleRate))
        guard interval > 0 else { return }
        var t = 0
        while t < frames {
            for i in 0..<min(interval / 3, frames - t) {
                let local = Double(i) / Double(sampleRate)
                let env = min(1, local / 0.04) * exp(-local * 3)
                let s = Float(sin(2 * Double.pi * 87 * local) * env) * gain
                left[t + i] += s
                right[t + i] += s
            }
            t += interval
        }
    }

    private static func normalize(_ left: inout [Float], _ right: inout [Float], ceiling: Float) {
        var peak: Float = 0.0001
        for i in 0..<left.count {
            peak = max(peak, max(abs(left[i]), abs(right[i])))
        }
        let g = ceiling / peak
        for i in 0..<left.count {
            left[i] *= g
            right[i] *= g
        }
    }

    private static func fadeEdges(_ left: inout [Float], _ right: inout [Float], ms: Int) {
        let fade = max(1, sampleRate * ms / 1000)
        let last = left.count
        for i in 0..<fade {
            let g = Float(i) / Float(fade)
            left[i] *= g
            right[i] *= g
            left[last - 1 - i] *= g
            right[last - 1 - i] *= g
        }
    }
}

enum WAVWriter {
    static func writeStereo(left: [Float], right: [Float], sampleRate: Int, to url: URL) throws {
        precondition(left.count == right.count)
        let frames = left.count
        var data = Data()
        data.append(ascii("RIFF"))
        data.append(le32(0))
        data.append(ascii("WAVE"))
        data.append(ascii("fmt "))
        data.append(le32(16))
        data.append(le16(1))
        data.append(le16(2))
        data.append(le32(UInt32(sampleRate)))
        data.append(le32(UInt32(sampleRate * 4)))
        data.append(le16(4))
        data.append(le16(16))
        data.append(ascii("data"))
        data.append(le32(UInt32(frames * 4)))
        data.reserveCapacity(data.count + frames * 4)
        for i in 0..<frames {
            data.append(le16(pcm(left[i])))
            data.append(le16(pcm(right[i])))
        }
        let riffSize = UInt32(data.count - 8)
        data.replaceSubrange(4..<8, with: le32(riffSize))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private static func pcm(_ sample: Float) -> UInt16 {
        let clipped = max(-1, min(1, sample))
        let value = Int16((clipped * Float(Int16.max)).rounded())
        return UInt16(bitPattern: value)
    }

    private static func ascii(_ text: String) -> Data {
        Data(text.utf8)
    }

    private static func le16(_ value: UInt16) -> Data {
        var v = value.littleEndian
        return Data(bytes: &v, count: 2)
    }

    private static func le32(_ value: UInt32) -> Data {
        var v = value.littleEndian
        return Data(bytes: &v, count: 4)
    }
}

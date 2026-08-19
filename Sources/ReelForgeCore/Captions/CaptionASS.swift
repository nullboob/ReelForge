import Foundation

/// Portable ASS writer. Same file Windows burns with ffmpeg `-vf ass=`.
public enum CaptionASS {
    public static func build(
        cues: [CaptionCue],
        look: CaptionLook,
        width: Int,
        height: Int,
        fontName: String? = nil
    ) -> String {
        let band = CaptionSafeArea.captionBand(width: Double(width), height: Double(height))
        let marginL = Int(band.x.rounded())
        let marginR = Int((Double(width) - band.x - band.width).rounded())
        let marginV = Int((Double(height) - band.y - band.height).rounded())
        let align = look.position == "bottom" ? 2 : 5
        let fill = look.fill
        let highlight = look.highlight
        let stroke = look.stroke
        let plate = look.plate
        let borderStyle = ["bar", "box"].contains(plate) ? 3 : 1
        let back = look.plateFill == "primaryHex" ? "#FF4D6D" : (look.plateFill ?? "#111111")
        let italic = look.font.lowercased().contains("italic") ? -1 : 0
        let cx = Double(width) / 2
        let cy = CaptionSafeArea.captionCenterY(height: Double(height))
        let font = fontName ?? look.font

        var lines: [String] = [
            "[Script Info]",
            "ScriptType: v4.00+",
            "WrapStyle: 2",
            "ScaledBorderAndShadow: yes",
            "PlayResX: \(width)",
            "PlayResY: \(height)",
            "",
            "[V4+ Styles]",
            "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding",
            "Style: Default,\(font),\(Int(look.size)),\(assColor(highlight)),\(assColor(fill)),\(assColor(stroke)),\(assColor(back, alpha: plate == "none" ? 80 : 0)),-1,\(italic),0,0,100,100,0,0,\(borderStyle),\(look.outline),\(look.shadow),\(align),\(marginL),\(marginR),\(marginV),1",
            "",
            "[Events]",
            "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text"
        ]

        for cue in CaptionSplitter.exclusive(cues) {
            var overrides = ["\\pos(\(Int(cx.rounded())),\(Int(cy.rounded())))"]
            switch look.animation {
            case "pop-scale":
                overrides.append("\\fscx118\\fscy118\\t(0,140,\\fscx100\\fscy100)")
            case "bounce":
                overrides.append("\\fscx110\\fscy120\\t(0,80,\\fscx100\\fscy100)\\t(80,160,\\fscx104\\fscy96)\\t(160,240,\\fscx100\\fscy100)")
            case "fade":
                overrides.append("\\fad(90,90)")
            case "slide-up":
                overrides.append("\\move(\(Int(cx.rounded())),\(Int(cy.rounded()) + 40),\(Int(cx.rounded())),\(Int(cy.rounded())),0,160)")
            case "glow-pulse":
                overrides.append("\\blur2\\t(0,200,\\blur6)\\t(200,400,\\blur2)")
            default:
                break
            }
            let prefix = "{" + overrides.joined() + "}"
            let start = assTime(cue.start)
            let end = assTime(cue.end)
            lines.append("Dialogue: 0,\(start),\(end),Default,,0,0,0,,\(prefix)\(cueText(cue, look: look))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func assColor(_ hex: String, alpha: Int = 0) -> String {
        let rgb = hexRGB(hex)
        return String(format: "&H%02X%02X%02X%02X", alpha, rgb.2, rgb.1, rgb.0)
    }

    public static func dialogueWindows(_ ass: String) -> [(Double, Double, String)] {
        ass.split(separator: "\n").compactMap { line in
            guard line.hasPrefix("Dialogue:") else { return nil }
            let payload = line.dropFirst("Dialogue:".count)
            let parts = payload.split(separator: ",", maxSplits: 9, omittingEmptySubsequences: false)
            guard parts.count >= 10 else { return nil }
            return (parseTime(String(parts[1]).trimmingCharacters(in: .whitespaces)),
                    parseTime(String(parts[2]).trimmingCharacters(in: .whitespaces)),
                    String(parts[9]))
        }
    }

    public static func usesASSFilterOnly() -> String { "ass=" }

    private static func cueText(_ cue: CaptionCue, look: CaptionLook) -> String {
        var tokens = cue.words.map(\.word)
        if tokens.isEmpty {
            tokens = cue.text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        }
        if look.allCaps { tokens = tokens.map { $0.uppercased() } }
        if look.animation == "typewriter" {
            let chars = Array(tokens.joined(separator: " "))
            let each = max(1, Int(((cue.duration / Double(max(1, chars.count))) * 100).rounded()))
            return chars.map { "{\\k\(each)}\(escape(String($0)))" }.joined()
        }
        if look.karaoke == "none" || look.animation == "fade" && look.id == "quiet-aesthetic-min" {
            return escape(tokens.joined(separator: " "))
        }
        let tag = look.karaoke == "fill" || look.animation == "karaoke-fill" ? "\\kf" : "\\k"
        let emphasis = cue.highlightWordIndex ?? CaptionSplitter.emphasisIndex(tokens)
        var parts: [String] = []
        for (index, word) in cue.words.enumerated() {
            let token = look.allCaps ? word.word.uppercased() : word.word
            let dur = max(1, Int((word.duration * 100).rounded()))
            var extra = ""
            if look.id == "color-switch-strobe" && index % 2 == 1 {
                extra = "\\1c" + assColor(look.highlight)
            } else if index == emphasis && look.primitive == "keyword-paint" {
                extra = "\\1c" + assColor(look.highlight)
            }
            parts.append("{\(tag)\(dur)\(extra)}\(escape(token))")
        }
        if parts.isEmpty {
            let each = max(1, Int((cue.duration / Double(max(1, tokens.count)) * 100).rounded()))
            parts = tokens.map { "{\(tag)\(each)}\(escape($0))" }
        }
        return parts.joined(separator: " ")
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "{", with: "\\{")
            .replacingOccurrences(of: "}", with: "\\}")
            .replacingOccurrences(of: "\n", with: "\\N")
    }

    private static func assTime(_ seconds: Double) -> String {
        let clamped = max(0, seconds)
        let hours = Int(clamped) / 3600
        let minutes = (Int(clamped) % 3600) / 60
        let secs = Int(clamped) % 60
        let cs = Int((clamped - Double(Int(clamped))) * 100)
        return String(format: "%d:%02d:%02d.%02d", hours, minutes, secs, cs)
    }

    private static func parseTime(_ value: String) -> Double {
        let parts = value.split(separator: ":")
        guard parts.count == 3 else { return 0 }
        let secParts = parts[2].split(separator: ".")
        let seconds = Double(secParts[0]) ?? 0
        let cs = Double(secParts.count > 1 ? secParts[1] : "0") ?? 0
        return (Double(parts[0]) ?? 0) * 3600 + (Double(parts[1]) ?? 0) * 60 + seconds + cs / 100
    }

    private static func hexRGB(_ hex: String) -> (Int, Int, Int) {
        var raw = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if raw.count == 8 { raw = String(raw.prefix(6)) }
        guard raw.count == 6, let value = Int(raw, radix: 16) else { return (255, 255, 255) }
        return ((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)
    }
}

import AppKit
import CoreText
import Foundation

enum HexColor {
    static func nsColor(_ hex: String, fallback: NSColor = .white) -> NSColor {
        var s = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if s.count == 6 { s.append("FF") }
        guard s.count == 8, let value = UInt64(s, radix: 16) else { return fallback }
        let r = CGFloat((value >> 24) & 0xFF) / 255
        let g = CGFloat((value >> 16) & 0xFF) / 255
        let b = CGFloat((value >> 8) & 0xFF) / 255
        let a = CGFloat(value & 0xFF) / 255
        return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    static func cgColor(_ hex: String, fallback: NSColor = .white) -> CGColor {
        nsColor(hex, fallback: fallback).cgColor
    }
}

enum AppFont {
    static func make(name: String, size: CGFloat, weight: String) -> NSFont {
        let resolved = name.localizedCaseInsensitiveContains("Arial") ? "Montserrat ExtraBold" : name
        if let font = NSFont(name: resolved, size: size) { return font }
        let mapped: NSFont.Weight
        switch weight.lowercased() {
        case "heavy", "black": mapped = .heavy
        case "bold": mapped = .bold
        case "demibold", "semibold": mapped = .semibold
        case "medium": mapped = .medium
        default: mapped = .semibold
        }
        return NSFont.systemFont(ofSize: size, weight: mapped)
    }

    static func caption(look: CaptionLook?, fallback: String, size: CGFloat, weight: String) -> NSFont {
        if let look, let url = CaptionCatalog.fontURL(file: look.fontFile) {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            if let name = CTFontCopyPostScriptName(CTFontCreateWithName(look.font as CFString, size, nil)) as String?,
               let font = NSFont(name: name, size: size) {
                return font
            }
            if let font = NSFont(name: look.font, size: size) {
                return font
            }
        }
        return make(name: fallback, size: size, weight: weight)
    }
}

enum ImageIO {
    static func loadCGImage(from url: URL) -> CGImage? {
        if let image = NSImage(contentsOf: url) {
            return cgImage(from: image)
        }
        return nil
    }

    static func cgImage(from image: NSImage) -> CGImage? {
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}

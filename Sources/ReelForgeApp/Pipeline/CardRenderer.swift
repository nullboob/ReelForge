import AppKit
import Foundation

enum CardRenderer {
    static func render(beat: Beat, preset: Preset, size: CGSize, channelName: String? = nil) -> NSImage? {
        let image = NSImage(size: size)
        image.lockFocus()
        guard let ctx = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return nil
        }
        ctx.saveGState()
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))

        let colors = preset.coverGradient.map { HexColor.cgColor($0) }
        if colors.count >= 2 {
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors as CFArray,
                locations: [0, 1]
            )
            if let gradient {
                ctx.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: size.height),
                    end: CGPoint(x: size.width, y: 0),
                    options: [.drawsAfterEndLocation, .drawsBeforeStartLocation]
                )
            }
        }

        drawVignette(ctx: ctx, size: size, amount: max(0.35, preset.colorGrade.vignette))
        drawGrain(ctx: ctx, size: size, seed: beat.index &* 17)

        let margin = size.width * 0.1
        var y = size.height * 0.72

        if let step = beat.stepNumber, step > 0 {
            let label = String(format: "%02d", step)
            let font = AppFont.make(name: preset.titleCard.font, size: min(64, size.width * 0.08), weight: "heavy")
            drawText(
                label,
                font: font,
                color: HexColor.nsColor(preset.captionStyle.highlight),
                in: CGRect(x: margin, y: y, width: size.width - margin * 2, height: font.pointSize + 12),
                ctx: ctx
            )
            y -= font.pointSize + 28
        } else {
            let eyebrow = beat.role.label.uppercased()
            let font = AppFont.make(name: "AvenirNext-DemiBold", size: min(22, size.width * 0.035), weight: "demibold")
            drawText(
                eyebrow,
                font: font,
                color: HexColor.nsColor(preset.captionStyle.highlight).withAlphaComponent(0.85),
                in: CGRect(x: margin, y: y, width: size.width - margin * 2, height: 36),
                ctx: ctx
            )
            y -= 48
        }

        let bodyFont = AppFont.make(
            name: preset.captionStyle.font,
            size: min(CGFloat(preset.captionStyle.size), size.width * 0.085),
            weight: preset.captionStyle.weight
        )
        drawWrapped(
            beat.text,
            font: bodyFont,
            color: HexColor.nsColor(preset.captionStyle.fill),
            stroke: HexColor.nsColor(preset.captionStyle.stroke).withAlphaComponent(0.85),
            in: CGRect(x: margin, y: size.height * 0.18, width: size.width - margin * 2, height: y - size.height * 0.18),
            ctx: ctx
        )

        if let name = channelName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            let markFont = AppFont.make(name: "AvenirNext-DemiBold", size: min(18, size.width * 0.028), weight: "demibold")
            let safe = CaptionSafeArea.rect(width: Double(size.width), height: Double(size.height))
            drawText(
                name.uppercased(),
                font: markFont,
                color: NSColor.white.withAlphaComponent(0.40),
                in: CGRect(x: safe.x, y: safe.y, width: safe.width, height: 22),
                ctx: ctx
            )
        }

        ctx.restoreGState()
        image.unlockFocus()
        return image
    }

    static func renderCaption(
        cue: CaptionCue,
        style: CaptionStyle,
        look: CaptionLook? = nil,
        canvas: CGSize,
        activeWord: Int?,
        primaryHex: String = "#FF4D6D"
    ) -> NSImage {
        let image = NSImage(size: canvas)
        image.lockFocus()
        guard let ctx = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return image
        }
        ctx.clear(CGRect(origin: .zero, size: canvas))
        let font = AppFont.caption(look: look, fallback: style.font, size: CGFloat(look?.size ?? style.size), weight: style.weight)
        var words = cue.text.split(separator: " ").map(String.init)
        if look?.allCaps == true {
            words = words.map { $0.uppercased() }
        }
        let highlight = activeWord ?? cue.highlightWordIndex
        let attr = NSMutableAttributedString()
        let accentGradient = look?.role == "accent" && !(look?.gradient.isEmpty ?? true)
        for (i, word) in words.enumerated() {
            let fill: NSColor
            if accentGradient && highlight != i {
                fill = HexColor.nsColor("#FFFFFF")
            } else if highlight == i {
                fill = HexColor.nsColor(look?.highlight ?? style.highlight)
            } else {
                fill = HexColor.nsColor(look?.fill ?? style.fill)
            }
            let strokeWidth = -CGFloat(max(2, look?.outline ?? 4)) * 0.45
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: fill,
                .strokeColor: HexColor.nsColor(look?.stroke ?? style.stroke),
                .strokeWidth: strokeWidth
            ]
            attr.append(NSAttributedString(string: word, attributes: attributes))
            if i < words.count - 1 {
                attr.append(NSAttributedString(string: " ", attributes: attributes))
            }
        }
        let textSize = attr.size()
        let safe = CaptionSafeArea.captionBand(width: Double(canvas.width), height: Double(canvas.height))
        let maxBox = min(safe.width, Double(textSize.width) + 48)
        let boxWidth = CGFloat(maxBox)
        let boxHeight = textSize.height + 20
        let boxX = CGFloat(safe.x) + (CGFloat(safe.width) - boxWidth) / 2
        let boxY: CGFloat
        let centered = (look?.position ?? style.position.rawValue) != "bottom"
        if centered {
            boxY = CGFloat(safe.y) + (CGFloat(safe.height) - boxHeight) / 2
        } else {
            boxY = CGFloat(safe.y) + 8
        }
        let box = CGRect(x: boxX, y: boxY, width: boxWidth, height: boxHeight)
        if let look, look.plate != "none" {
            var plate = look.plateFill ?? "#111111"
            if plate == "primaryHex" { plate = primaryHex }
            let color = HexColor.nsColor(plate).withAlphaComponent(look.plate == "soft" ? 0.66 : 0.9)
            color.setFill()
            let path = NSBezierPath(roundedRect: box, xRadius: look.plate == "pill" ? 22 : 8, yRadius: look.plate == "pill" ? 22 : 8)
            path.fill()
        }
        if let look, !look.gradient.isEmpty, look.role == "accent" {
            // Multi-stop fills are CGGradient (not CAGradientLayer). 2-stop is allowed; 3+ stays CG.
            let colors = look.gradient.map { HexColor.cgColor($0) }
            if colors.count >= 2 {
                let locations = (0..<colors.count).map { CGFloat($0) / CGFloat(max(1, colors.count - 1)) }
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: locations) {
                    ctx.saveGState()
                    let start: CGPoint
                    let end: CGPoint
                    if look.angle == 135 {
                        start = CGPoint(x: box.minX, y: box.maxY)
                        end = CGPoint(x: box.maxX, y: box.minY)
                    } else {
                        start = CGPoint(x: box.minX, y: box.midY)
                        end = CGPoint(x: box.maxX, y: box.midY)
                    }
                    ctx.addPath(CGPath(roundedRect: box.insetBy(dx: 8, dy: 4), cornerWidth: 8, cornerHeight: 8, transform: nil))
                    ctx.clip()
                    ctx.drawLinearGradient(gradient, start: start, end: end, options: [])
                    ctx.restoreGState()
                }
            }
        }
        let textRect = CGRect(
            x: box.minX + 16,
            y: box.minY + 8,
            width: box.width - 32,
            height: textSize.height + 4
        )
        attr.draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        image.unlockFocus()
        _ = ctx
        return image
    }

    static func drawVignette(ctx: CGContext, size: CGSize, amount: Double) {
        guard amount > 0.01 else { return }
        ctx.saveGState()
        let colors = [
            NSColor.clear.cgColor,
            NSColor.black.withAlphaComponent(CGFloat(min(0.85, amount))).cgColor
        ] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.45, 1]) {
            ctx.drawRadialGradient(
                gradient,
                startCenter: CGPoint(x: size.width / 2, y: size.height / 2),
                startRadius: 0,
                endCenter: CGPoint(x: size.width / 2, y: size.height / 2),
                endRadius: hypot(size.width, size.height) * 0.62,
                options: [.drawsAfterEndLocation]
            )
        }
        ctx.restoreGState()
    }

    static func drawGrain(ctx: CGContext, size: CGSize, seed: Int) {
        ctx.saveGState()
        var rng = UInt64(truncatingIfNeeded: seed &+ 1_013_903_223)
        for _ in 0..<Int(size.width * size.height * 0.00035) {
            rng = rng &* 6_364_136_223_846_793_005 &+ 1
            let x = CGFloat(rng % UInt64(max(1, Int(size.width))))
            rng = rng &* 6_364_136_223_846_793_005 &+ 1
            let y = CGFloat(rng % UInt64(max(1, Int(size.height))))
            ctx.setFillColor(NSColor.white.withAlphaComponent(0.08).cgColor)
            ctx.fill(CGRect(x: x, y: y, width: 1.2, height: 1.2))
        }
        ctx.restoreGState()
    }

    private static func drawText(_ text: String, font: NSFont, color: NSColor, in rect: CGRect, ctx: CGContext) {
        let attr: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        (text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin], attributes: attr)
        _ = ctx
    }

    private static func drawWrapped(
        _ text: String,
        font: NSFont,
        color: NSColor,
        stroke: NSColor,
        in rect: CGRect,
        ctx: CGContext
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.lineBreakMode = .byWordWrapping
        let attr: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .strokeColor: stroke,
            .strokeWidth: -2.4,
            .paragraphStyle: paragraph
        ]
        (text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attr)
        _ = ctx
    }
}

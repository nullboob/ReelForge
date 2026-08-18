import AppKit
import Foundation

enum ThumbnailRenderer {
    static func render(hook: String, channel: ChannelKit, preset: Preset, to url: URL) {
        let size = CGSize(width: 1280, height: 720)
        let image = NSImage(size: size)
        image.lockFocus()
        guard let ctx = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return
        }
        let colors = [
            HexColor.cgColor(channel.primaryHex),
            HexColor.cgColor(preset.coverGradient.last ?? "#111111")
        ]
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1]) {
            ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
        }
        CardRenderer.drawVignette(ctx: ctx, size: size, amount: 0.45)
        let eyebrow = channel.name.isEmpty ? "REELFORGE" : channel.name.uppercased()
        let small = AppFont.make(name: "AvenirNext-DemiBold", size: 22, weight: "demibold")
        (eyebrow as NSString).draw(
            at: CGPoint(x: 64, y: 600),
            withAttributes: [.font: small, .foregroundColor: HexColor.nsColor(channel.accentHex)]
        )
        let font = AppFont.make(name: "AvenirNext-Heavy", size: 54, weight: "heavy")
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        (hook as NSString).draw(
            with: CGRect(x: 64, y: 160, width: 1150, height: 400),
            options: [.usesLineFragmentOrigin],
            attributes: [
                .font: font,
                .foregroundColor: NSColor.white,
                .strokeColor: NSColor.black.withAlphaComponent(0.7),
                .strokeWidth: -2.2,
                .paragraphStyle: paragraph
            ]
        )
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.86])
        else { return }
        try? jpeg.write(to: url)
    }
}

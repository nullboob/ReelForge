import AVFoundation
import AppKit
import CoreVideo
import Foundation

enum ClipWriter {
    static func writeStill(
        image: CGImage,
        duration: Double,
        size: CGSize,
        kenBurns: KenBurnsParams,
        grade: ColorGrade,
        grain: Bool,
        captions: [CaptionCue],
        captionStyle: CaptionStyle,
        title: String?,
        titleStyle: TitleCardStyle,
        stepNumber: Int?,
        timelineOffset: Double,
        logo: CGImage?,
        outputURL: URL
    ) async throws {
        try await write(duration: duration, size: size, outputURL: outputURL) { ctx, time in
            drawKenBurns(image, ctx: ctx, size: size, kenBurns: kenBurns, t: time, duration: duration)
            applyGrade(ctx: ctx, size: size, grade: grade)
            if grain { CardRenderer.drawGrain(ctx: ctx, size: size, seed: Int(time * 30) &+ 3) }
            drawOverlays(
                ctx: ctx,
                size: size,
                time: time + timelineOffset,
                captions: captions,
                captionStyle: captionStyle,
                title: title,
                titleStyle: titleStyle,
                stepNumber: stepNumber,
                logo: logo
            )
        }
    }

    static func writeVideo(
        source: URL,
        duration: Double,
        size: CGSize,
        grade: ColorGrade,
        grain: Bool,
        captions: [CaptionCue],
        captionStyle: CaptionStyle,
        title: String?,
        titleStyle: TitleCardStyle,
        stepNumber: Int?,
        timelineOffset: Double,
        logo: CGImage?,
        outputURL: URL
    ) async throws {
        let asset = AVURLAsset(url: source)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = CGSize(width: size.width * 1.5, height: size.height * 1.5)
        var sourceDuration = CMTimeGetSeconds(asset.duration)
        if sourceDuration.isNaN || sourceDuration <= 0 {
            sourceDuration = duration
        }
        sourceDuration = max(0.2, sourceDuration)

        try await write(duration: duration, size: size, outputURL: outputURL) { ctx, time in
            let sourceTime = CMTime(seconds: min(sourceDuration - 0.01, time.truncatingRemainder(dividingBy: sourceDuration)), preferredTimescale: 600)
            let frame = try? generator.copyCGImage(at: sourceTime, actualTime: nil)
            if let frame {
                drawAspectFill(frame, ctx: ctx, size: size)
            } else {
                ctx.setFillColor(NSColor.black.cgColor)
                ctx.fill(CGRect(origin: .zero, size: size))
            }
            applyGrade(ctx: ctx, size: size, grade: grade)
            if grain { CardRenderer.drawGrain(ctx: ctx, size: size, seed: Int(time * 30)) }
            drawOverlays(
                ctx: ctx,
                size: size,
                time: time + timelineOffset,
                captions: captions,
                captionStyle: captionStyle,
                title: title,
                titleStyle: titleStyle,
                stepNumber: stepNumber,
                logo: logo
            )
        }
    }

    private static func write(
        duration: Double,
        size: CGSize,
        outputURL: URL,
        draw: @escaping (CGContext, Double) throws -> Void
    ) async throws {
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 8_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: 30
            ]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height)
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attrs)
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let fps = 30
        let frames = max(1, Int((duration * Double(fps)).rounded()))
        var pool = adaptor.pixelBufferPool

        for index in 0..<frames {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            if pool == nil { pool = adaptor.pixelBufferPool }
            guard let pool else { throw ClipWriteError.noPixelBuffer }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { throw ClipWriteError.noPixelBuffer }
            try drawInto(buffer, size: size) { ctx in
                try draw(ctx, Double(index) / Double(fps))
            }
            let time = CMTime(value: CMTimeValue(index), timescale: CMTimeScale(fps))
            if !adaptor.append(buffer, withPresentationTime: time) {
                throw ClipWriteError.appendFailed
            }
        }

        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed {
            throw writer.error ?? ClipWriteError.appendFailed
        }
    }

    private static func drawInto(_ buffer: CVPixelBuffer, size: CGSize, draw: (CGContext) throws -> Void) throws {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let data = CVPixelBufferGetBaseAddress(buffer) else { throw ClipWriteError.noPixelBuffer }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        guard let ctx = CGContext(
            data: data,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { throw ClipWriteError.noPixelBuffer }
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))
        try draw(ctx)
    }

    private static func drawKenBurns(
        _ image: CGImage,
        ctx: CGContext,
        size: CGSize,
        kenBurns: KenBurnsParams,
        t: Double,
        duration: Double
    ) {
        let p = duration > 0 ? min(1, max(0, t / duration)) : 0
        var scale = kenBurns.startScale + (kenBurns.endScale - kenBurns.startScale) * p
        if kenBurns.pulse {
            scale *= 1 + 0.03 * sin(p * .pi * 4)
        }
        let ox = kenBurns.startX + (kenBurns.endX - kenBurns.startX) * p
        let oy = kenBurns.startY + (kenBurns.endY - kenBurns.startY) * p
        drawAspectFill(
            image,
            ctx: ctx,
            size: size,
            scale: scale,
            offset: CGPoint(x: ox * size.width, y: oy * size.height)
        )
    }

    private static func drawAspectFill(
        _ image: CGImage,
        ctx: CGContext,
        size: CGSize,
        scale: Double = 1,
        offset: CGPoint = .zero
    ) {
        let iw = CGFloat(image.width)
        let ih = CGFloat(image.height)
        let fill = max(size.width / iw, size.height / ih) * CGFloat(scale)
        let dw = iw * fill
        let dh = ih * fill
        let rect = CGRect(
            x: (size.width - dw) / 2 + offset.x,
            y: (size.height - dh) / 2 + offset.y,
            width: dw,
            height: dh
        )
        ctx.saveGState()
        ctx.clip(to: CGRect(origin: .zero, size: size))
        ctx.draw(image, in: rect)
        ctx.restoreGState()
    }

    private static func applyGrade(ctx: CGContext, size: CGSize, grade: ColorGrade) {
        let rect = CGRect(origin: .zero, size: size)
        if grade.contrast != 1 {
            let amount = CGFloat(min(0.35, abs(grade.contrast - 1)))
            ctx.setFillColor((grade.contrast > 1 ? NSColor.black : NSColor.white).withAlphaComponent(amount * 0.45).cgColor)
            ctx.setBlendMode(.overlay)
            ctx.fill(rect)
            ctx.setBlendMode(.normal)
        }
        if abs(grade.warmth) > 0.01 {
            let warm = grade.warmth > 0
                ? NSColor(srgbRed: 1, green: 0.72, blue: 0.35, alpha: CGFloat(min(0.28, abs(grade.warmth))))
                : NSColor(srgbRed: 0.35, green: 0.5, blue: 1, alpha: CGFloat(min(0.28, abs(grade.warmth))))
            ctx.setFillColor(warm.cgColor)
            ctx.setBlendMode(.overlay)
            ctx.fill(rect)
            ctx.setBlendMode(.normal)
        }
        if grade.saturation < 0.95 {
            ctx.setFillColor(NSColor.gray.withAlphaComponent(CGFloat((1 - grade.saturation) * 0.35)).cgColor)
            ctx.setBlendMode(.saturation)
            ctx.fill(rect)
            ctx.setBlendMode(.normal)
        }
        CardRenderer.drawVignette(ctx: ctx, size: size, amount: grade.vignette)
    }

    private static func drawOverlays(
        ctx: CGContext,
        size: CGSize,
        time: Double,
        captions: [CaptionCue],
        captionStyle: CaptionStyle,
        title: String?,
        titleStyle: TitleCardStyle,
        stepNumber: Int?,
        logo: CGImage?
    ) {
        if let logo {
            drawWatermark(logo, ctx: ctx, size: size)
        }

        if let stepNumber, stepNumber > 0 {
            let font = AppFont.make(name: titleStyle.font, size: min(42, size.width * 0.055), weight: "bold")
            let text = String(format: "%02d", stepNumber)
            let attr: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: HexColor.nsColor(titleStyle.fill)
            ]
            (text as NSString).draw(
                at: CGPoint(x: size.width * 0.08, y: size.height * 0.88),
                withAttributes: attr
            )
        }

        if let title, time < 1.55 {
            let font = AppFont.make(name: titleStyle.font, size: CGFloat(titleStyle.size) * 0.72, weight: "bold")
            let attr: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: HexColor.nsColor(titleStyle.fill),
                .strokeColor: NSColor.black.withAlphaComponent(0.8),
                .strokeWidth: -2
            ]
            let rect = CGRect(x: size.width * 0.08, y: size.height * 0.62, width: size.width * 0.84, height: size.height * 0.2)
            (title as NSString).draw(with: rect, options: [.usesLineFragmentOrigin], attributes: attr)
        }

        guard let cue = captions.first(where: { time >= $0.start && time < $0.end }) else { return }
        var active: Int?
        switch captionStyle.animation {
        case .wordByWord, .karaoke:
            active = cue.words.lastIndex(where: { time >= $0.start })
        case .pop:
            active = cue.highlightWordIndex
        }
        let image = CardRenderer.renderCaption(cue: cue, style: captionStyle, canvas: size, activeWord: active)
        if let cg = ImageIO.cgImage(from: image) {
            var alpha: CGFloat = 1
            if captionStyle.animation == .pop {
                let local = time - cue.start
                if local < 0.12 { alpha = CGFloat(local / 0.12) }
            }
            ctx.saveGState()
            ctx.setAlpha(alpha)
            ctx.draw(cg, in: CGRect(origin: .zero, size: size))
            ctx.restoreGState()
        }
    }

    private static func drawWatermark(_ logo: CGImage, ctx: CGContext, size: CGSize) {
        let maxW = size.width * 0.14
        let maxH = size.height * 0.09
        let iw = CGFloat(logo.width)
        let ih = CGFloat(logo.height)
        guard iw > 1, ih > 1 else { return }
        let scale = min(maxW / iw, maxH / ih)
        let w = iw * scale
        let h = ih * scale
        let insetX = size.width * 0.055
        let insetY = size.height * 0.055
        ctx.saveGState()
        ctx.setAlpha(0.82)
        ctx.draw(logo, in: CGRect(x: size.width - insetX - w, y: size.height - insetY - h, width: w, height: h))
        ctx.restoreGState()
    }
}

enum ClipWriteError: Error {
    case noPixelBuffer
    case appendFailed
}

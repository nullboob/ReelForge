import AppKit
import Foundation

struct FootageAssignment {
    var asset: AssetRef
    var fileURL: URL
}

struct FootageService {
    func gather(
        beats: [Beat],
        preset: Preset,
        aspect: AspectRatio,
        workDir: URL,
        localFiles: [URL],
        unsplashKey: String?,
        useUnsplash: Bool,
        useLocalAI: Bool,
        onProgress: @MainActor @escaping (String) -> Void
    ) async -> (assignments: [String: FootageAssignment], attributions: [UnsplashAttribution], warnings: [String]) {
        var assignments: [String: FootageAssignment] = [:]
        var attributions: [UnsplashAttribution] = []
        var warnings: [String] = []
        let size = aspect.pixelSize
        let localMedia = localFiles.filter { isMedia($0) }

        if useUnsplash, unsplashKey == nil {
            warnings.append("No Unsplash key — using styled cards. Add one in Settings.")
        }

        for (index, beat) in beats.enumerated() {
            await onProgress("Fetching B-roll for beat \(index + 1)/\(beats.count)")
            let destImage = workDir.appendingPathComponent("beat-\(index).png")

            if let local = localMedia[safe: index] ?? localMedia[safe: index % max(localMedia.count, 1)],
               !localMedia.isEmpty {
                let copied = workDir.appendingPathComponent("local-\(index)-\(local.lastPathComponent)")
                if copyItem(local, to: copied) {
                    let kind: AssetKind = isVideo(local) ? .video : .image
                    assignments[beat.id] = FootageAssignment(
                        asset: AssetRef(id: "local-\(index)", kind: kind, relativePath: copied.lastPathComponent, beatID: beat.id),
                        fileURL: copied
                    )
                    continue
                }
            }

            if useLocalAI {
                let prompt = "\(beat.text). \(preset.aiImageStyleSuffix)"
                if index == 0 {
                    let destVideo = workDir.appendingPathComponent("beat-\(index).mp4")
                    await onProgress("Trying ComfyUI video for the hook beat")
                    if await LocalVideoClient.shared.generateVideo(prompt: prompt, startImage: nil, to: destVideo),
                       FileManager.default.fileExists(atPath: destVideo.path) {
                        assignments[beat.id] = FootageAssignment(
                            asset: AssetRef(id: "comfy-video-\(index)", kind: .video, relativePath: destVideo.lastPathComponent, beatID: beat.id),
                            fileURL: destVideo
                        )
                        continue
                    }
                    let caps = await ComfyUIClient.shared.capabilities()
                    if caps.online, caps.canImageToVideo {
                        warnings.append("ComfyUI shows LTX/I2V nodes. Save an API-format workflow as Application Support/ReelForge/comfy-i2v.json to use it.")
                    }
                }
                await onProgress("Asking ComfyUI for still \(index + 1)/\(beats.count)")
                if await LocalAIClient.shared.generateImage(prompt: prompt, size: size, to: destImage),
                   FileManager.default.fileExists(atPath: destImage.path) {
                    assignments[beat.id] = FootageAssignment(
                        asset: AssetRef(id: "ai-\(index)", kind: .image, relativePath: destImage.lastPathComponent, beatID: beat.id),
                        fileURL: destImage
                    )
                    continue
                }
            }

            if useUnsplash, let key = unsplashKey {
                if let photo = await UnsplashClient.shared.search(
                    query: beat.unsplashQuery,
                    accessKey: key,
                    portrait: aspect != .landscape
                ), await UnsplashClient.shared.download(photo, to: destImage) {
                    let attr = UnsplashAttribution(
                        photographer: photo.photographer,
                        photographerURL: photo.photographerURL,
                        photoURL: photo.pageURL,
                        beatID: beat.id
                    )
                    attributions.append(attr)
                    assignments[beat.id] = FootageAssignment(
                        asset: AssetRef(id: photo.id, kind: .image, relativePath: destImage.lastPathComponent, beatID: beat.id, attribution: attr),
                        fileURL: destImage
                    )
                    continue
                }
            }

            if let image = CardRenderer.render(beat: beat, preset: preset, size: CGSize(width: size.width, height: size.height)),
               let data = image.pngData(),
               (try? data.write(to: destImage)) != nil {
                assignments[beat.id] = FootageAssignment(
                    asset: AssetRef(id: "card-\(index)", kind: .generatedCard, relativePath: destImage.lastPathComponent, beatID: beat.id),
                    fileURL: destImage
                )
            }
        }

        if assignments.count < beats.count {
            warnings.append("Some beats used fallback cards so export could finish.")
        }
        return (assignments, attributions, warnings)
    }

    private func isMedia(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["mp4", "mov", "m4v", "jpg", "jpeg", "png", "heic", "webp", "tif", "tiff"].contains(ext)
    }

    private func isVideo(_ url: URL) -> Bool {
        ["mp4", "mov", "m4v"].contains(url.pathExtension.lowercased())
    }

    private func copyItem(_ src: URL, to dst: URL) -> Bool {
        let accessed = src.startAccessingSecurityScopedResource()
        defer { if accessed { src.stopAccessingSecurityScopedResource() } }
        do {
            if FileManager.default.fileExists(atPath: dst.path) {
                try FileManager.default.removeItem(at: dst)
            }
            try FileManager.default.copyItem(at: src, to: dst)
            return true
        } catch {
            return false
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension NSImage {
    func pngData() -> Data? {
        guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

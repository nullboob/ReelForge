import XCTest
@testable import ReelForgeCore

final class SetupWizardTests: XCTestCase {
    func testRecommendInstantWithoutGPU() {
        let hw = HardwareSnapshot(nvidia: false, vramGB: 0, appleGPU: false, ramGB: 8, diskFreeGB: 20)
        XCTAssertEqual(SetupWizard.recommend(hw), .instant)
    }

    func testRecommendFastVideoOnNvidia8() {
        let hw = HardwareSnapshot(nvidia: true, vramGB: 8, appleGPU: false, ramGB: 32, diskFreeGB: 200)
        XCTAssertEqual(SetupWizard.recommend(hw), .fastVideo)
    }

    func testRecommendFastImageOnAppleGPU() {
        let hw = HardwareSnapshot(nvidia: false, vramGB: 0, appleGPU: true, ramGB: 16, diskFreeGB: 64)
        XCTAssertEqual(SetupWizard.recommend(hw), .fastImage)
    }

    func testQualityHiddenUnless16GB() {
        let low = HardwareSnapshot(nvidia: true, vramGB: 8, appleGPU: false, ramGB: 16, diskFreeGB: 80)
        let high = HardwareSnapshot(nvidia: true, vramGB: 16, appleGPU: false, ramGB: 32, diskFreeGB: 80)
        XCTAssertFalse(SetupWizard.showQuality(low))
        XCTAssertTrue(SetupWizard.showQuality(high))
        let manifest = try! SetupWizard.loadManifest()
        XCTAssertFalse(SetupWizard.visiblePacks(low, from: manifest).contains { $0.id == "quality-video" })
        XCTAssertTrue(SetupWizard.visiblePacks(high, from: manifest).contains { $0.id == "quality-video" })
    }

    func testManifestDecodesAndKeepsHonestURLs() throws {
        let manifest = try SetupWizard.loadManifest()
        XCTAssertEqual(manifest.title, "Set up ReelForge in one click")
        XCTAssertTrue(manifest.packs.contains { $0.id == "instant" })
        XCTAssertTrue(manifest.files.contains { $0.id == "ltx-gguf" && ($0.urls.first?.contains("huggingface.co") == true) })
        for file in manifest.files where file.urls.isEmpty {
            XCTAssertFalse(file.note.isEmpty, "\(file.id) needs a packaged-at-build note")
        }
        let fast = ModelDownload.files(for: .fastVideo, in: manifest)
        XCTAssertTrue(fast.contains { $0.id == "ltx-gguf" })
        XCTAssertFalse(ModelDownload.downloadable(fast).isEmpty)
        let dest = ModelDownload.destination(for: fast[0], modelsRoot: URL(fileURLWithPath: "/tmp/models"))
        XCTAssertTrue(dest.path.hasSuffix(fast[0].dest))
    }

    func testEmptyChecksumPasses() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rf-empty-sha-\(UUID().uuidString)")
        try Data("ok".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(try ModelDownload.verifyChecksum(at: url, expected: ""))
    }

    func testScanMarksGGUFVideoReady() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("reelforge-gguf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        FileManager.default.createFile(atPath: root.appendingPathComponent("ltx-2.3-22b-distilled-1.1-Q5_K_S.gguf").path, contents: Data("fake".utf8))
        let scan = ModelCatalog.scan(modelsDir: root.path, roots: [root])
        XCTAssertTrue(scan.videoReady)
        XCTAssertEqual(scan.slots.first { $0.id == "ltx-gguf" }?.ready, true)
    }
}

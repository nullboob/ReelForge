import XCTest
@testable import ReelForgeCore

final class ModelCatalogTests: XCTestCase {
    func testScanMarksExistingWeightsReady() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("reelforge-models-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        FileManager.default.createFile(atPath: root.appendingPathComponent("ltx-2.3-22b-distilled.safetensors").path, contents: Data("fake".utf8))
        FileManager.default.createFile(atPath: root.appendingPathComponent("qwen-image.safetensors").path, contents: Data("fake".utf8))

        let scan = ModelCatalog.scan(modelsDir: root.path, roots: [root])
        XCTAssertTrue(scan.videoReady)
        XCTAssertTrue(scan.imageReady)
        XCTAssertTrue(scan.anyReady)
        XCTAssertEqual(scan.slots.first { $0.id == "ltx-distilled" }?.ready, true)
        XCTAssertEqual(scan.slots.first { $0.id == "qwen-image" }?.ready, true)
        XCTAssertEqual(scan.slots.first { $0.id == "wan-22" }?.ready, false)
    }

    func testAlignedSizeAndFrameCount() {
        let size = ModelCatalog.alignedSize(width: 1080, height: 1920)
        XCTAssertEqual(size.0 % 32, 0)
        XCTAssertEqual(size.1 % 32, 0)
        let frames = ModelCatalog.frameCount(seconds: 3)
        XCTAssertEqual(frames % 8, 1)
        XCTAssertGreaterThanOrEqual(frames, 9)
    }
}

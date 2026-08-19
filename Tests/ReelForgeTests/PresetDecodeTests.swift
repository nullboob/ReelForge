import XCTest
@testable import ReelForgeCore

final class PresetDecodeTests: XCTestCase {
    func testLoadsAllBundledPresets() throws {
        let presets = try loadPresets()
        XCTAssertEqual(presets.count, 14)
        XCTAssertEqual(presets.map(\.id), PresetCatalog.expectedIDs)
    }

    func testEachPresetHasRequiredStyleFields() throws {
        for preset in try loadPresets() {
            XCTAssertFalse(preset.name.isEmpty, preset.id)
            XCTAssertFalse(preset.tagline.isEmpty, preset.id)
            XCTAssertGreaterThanOrEqual(preset.coverGradient.count, 2, preset.id)
            XCTAssertTrue([15, 20, 30, 45, 60, 180, 240, 300, 480].contains(preset.durationSec), preset.id)
            XCTAssertGreaterThan(preset.pace.cutMinSec, 0, preset.id)
            XCTAssertGreaterThan(preset.pace.cutMaxSec, preset.pace.cutMinSec, preset.id)
            XCTAssertGreaterThan(preset.captionStyle.maxWordsPerCard, 0, preset.id)
            XCTAssertFalse(preset.captionStyle.font.isEmpty, preset.id)
            XCTAssertFalse(preset.footage.unsplashQueries.isEmpty, preset.id)
            XCTAssertFalse(preset.aiImageStyleSuffix.isEmpty, preset.id)
            XCTAssertGreaterThan(preset.music.bpm, 50, preset.id)
        }
    }

    func testJSONRoundTrip() throws {
        let presets = try loadPresets()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let decoder = JSONDecoder()
        for preset in presets {
            let data = try encoder.encode(preset)
            let decoded = try decoder.decode(Preset.self, from: data)
            XCTAssertEqual(decoded, preset)
        }
    }

    func testViralHookMatchesProductBrief() throws {
        let viral = try loadPresets().first { $0.id == "viral-hook" }
        XCTAssertEqual(viral?.aspect, .vertical)
        XCTAssertEqual(viral?.durationSec, 15)
        XCTAssertEqual(viral?.pace.cutMinSec, 0.8)
        XCTAssertEqual(viral?.pace.cutMaxSec, 1.4)
        XCTAssertEqual(viral?.pace.transition, .hardCut)
    }

    private func loadPresets() throws -> [Preset] {
        if let dir = PresetCatalog.bundledDirectory() ?? PresetCatalog.sourceTreeDirectory() {
            return try PresetCatalog.load(from: dir)
        }
        throw PresetCatalogError.directoryMissing
    }
}

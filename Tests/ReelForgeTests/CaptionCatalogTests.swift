import XCTest
@testable import ReelForgeCore

final class CaptionCatalogTests: XCTestCase {
    func testCatalogHasThirtyResearchStyles() throws {
        let file = try CaptionCatalog.loadFile()
        XCTAssertGreaterThanOrEqual(file.styles.count, 30)
        let ids = Set(file.styles.map(\.id))
        for required in CaptionCatalog.requiredIDs {
            XCTAssertTrue(ids.contains(required), required)
        }
        XCTAssertEqual(CaptionCatalog.defaultID(forPreset: "viral-hook"), "tiktok-classic-outline")
        XCTAssertEqual(CaptionCatalog.resolve(id: "dynamic-minimal"), "tiktok-classic-outline")
        XCTAssertEqual(CaptionCatalog.resolve(id: "hormozi-classic"), "hormozi-yellow-pop")
        let look = CaptionCatalog.look(id: "hormozi-classic")
        XCTAssertEqual(look.id, "hormozi-yellow-pop")
        XCTAssertEqual(look.highlight.uppercased(), "#F7C204")
        XCTAssertEqual(look.asCaptionStyle().animation, .pop)
        XCTAssertEqual(CaptionCatalog.look(id: "sunset-fill").id, "gradient-sunset-fill")
        XCTAssertEqual(CaptionCatalog.look(id: "gradient-sunset-fill").renderer, "png")
        XCTAssertEqual(CaptionCatalog.look(id: "tiktok-classic-outline").renderer, "ass")
    }

    func testASSKaraokeParity() throws {
        let look = CaptionCatalog.look(id: "karaoke-yellow-sweep")
        let cue = CaptionCue(
            id: "c0",
            text: "Stop scrolling now",
            start: 0,
            duration: 1.2,
            words: [
                WordTiming(word: "Stop", start: 0, duration: 0.3),
                WordTiming(word: "scrolling", start: 0.3, duration: 0.5),
                WordTiming(word: "now", start: 0.8, duration: 0.4)
            ],
            highlightWordIndex: 1
        )
        let ass = CaptionASS.build(cues: [cue], look: look, width: 1080, height: 1920)
        XCTAssertTrue(ass.contains("PrimaryColour"))
        XCTAssertTrue(ass.contains(CaptionASS.assColor(look.highlight)))
        XCTAssertTrue(ass.contains(CaptionASS.assColor(look.fill)))
        XCTAssertTrue(ass.contains("\\kf") || ass.contains("\\k"))
        XCTAssertFalse(ass.contains("subtitles="))
        let windows = CaptionASS.dialogueWindows(ass)
        XCTAssertFalse(windows.isEmpty)
        XCTAssertEqual(CaptionASS.usesASSFilterOnly(), "ass=")
        let posY = CaptionSafeArea.captionCenterY(height: 1920)
        XCTAssertGreaterThanOrEqual(posY, 700)
        XCTAssertLessThanOrEqual(posY, 1360)
    }

    func testCaptionBandAndWordClock() {
        let band = CaptionSafeArea.captionBand(width: 1080, height: 1920)
        XCTAssertEqual(band.y, 700, accuracy: 1)
        XCTAssertEqual(band.y + band.height, 1360, accuracy: 1)
        XCTAssertEqual(CaptionSafeArea.maxWords(forPresetID: "viral-hook", requested: 12), 3)
        XCTAssertEqual(CaptionSafeArea.maxWords(forPresetID: "viral-hook", requested: 1), 1)
        let cues = CaptionSplitter.align(text: "one two three four five six", duration: 9, maxWordsPerCard: 3)
        XCTAssertTrue(cues.allSatisfy { $0.text.split(separator: " ").count <= 3 })
        XCTAssertTrue(cues.allSatisfy { $0.duration <= 2.05 || cues.count == 1 })
        XCTAssertTrue(cues.allSatisfy { $0.highlightWordIndex != nil })
    }
}

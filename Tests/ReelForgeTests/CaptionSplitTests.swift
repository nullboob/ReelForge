import XCTest
@testable import ReelForgeCore

final class CaptionSplitTests: XCTestCase {
    func testPacksToMaxWordsAndCoversDuration() {
        let text = "one two three four five six seven eight nine"
        let cues = CaptionSplitter.align(text: text, duration: 9, maxWordsPerCard: 4)
        XCTAssertEqual(cues.count, 3)
        XCTAssertTrue(cues.allSatisfy { $0.text.split(separator: " ").count <= 4 })
        XCTAssertEqual(cues.first?.start ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(cues.last?.end ?? 0, 9, accuracy: 0.08)
        let words = cues.flatMap(\.words)
        XCTAssertEqual(words.count, 9)
        XCTAssertEqual(words.last?.start ?? 0, cues.last!.start, accuracy: 2.0)
    }

    func testEmptyTextReturnsNoCues() {
        XCTAssertTrue(CaptionSplitter.align(text: "   ", duration: 10, maxWordsPerCard: 5).isEmpty)
    }

    func testBeatAlignedCaptionsStayInsideBeats() throws {
        let dir = try XCTUnwrap(PresetCatalog.bundledDirectory() ?? PresetCatalog.sourceTreeDirectory())
        let preset = try PresetCatalog.load(from: dir).first { $0.id == "viral-hook" }!
        let script = ScriptWriter.write(topic: "3 reasons your morning walk beats the gym", presetID: preset.id)
        let board = try StoryboardBuilder.build(script: script, preset: preset, duration: 15)
        let cues = CaptionSplitter.cues(from: script, duration: 15, maxWordsPerCard: 5, storyboard: board)
        XCTAssertFalse(cues.isEmpty)
        for cue in cues {
            XCTAssertGreaterThanOrEqual(cue.start, -0.001)
            XCTAssertLessThanOrEqual(cue.end, board.duration + 0.15)
            XCTAssertFalse(cue.text.isEmpty)
        }
    }

    func testSentenceBreaksPreferNaturalCards() {
        let text = "First sentence lands. Second sentence follows. Third stays short."
        let cues = CaptionSplitter.align(text: text, duration: 6, maxWordsPerCard: 8)
        XCTAssertGreaterThanOrEqual(cues.count, 3)
        XCTAssertTrue(cues[0].text.lowercased().contains("first"))
    }

    func testBurnedCuesDoNotOverlap() throws {
        let colliding = [
            CaptionCue(id: "a", text: "Stop scrolling.", start: 0, duration: 2, words: []),
            CaptionCue(id: "b", text: "Morning walk beats the", start: 0.4, duration: 1.8, words: [])
        ]
        XCTAssertFalse(CaptionSplitter.overlappingPairs(colliding).isEmpty)
        let fixed = CaptionSplitter.exclusive(colliding)
        XCTAssertTrue(CaptionSplitter.overlappingPairs(fixed).isEmpty)

        let dir = try XCTUnwrap(PresetCatalog.bundledDirectory() ?? PresetCatalog.sourceTreeDirectory())
        let preset = try PresetCatalog.load(from: dir).first { $0.id == "viral-hook" }!
        let script = GeneratedScript(
            hook: "Stop scrolling. Morning walk beats the gym.",
            body: ["Reason one is free daylight.", "Reason two is a quieter head."],
            cta: "Follow for the next walk.",
            source: .user
        )
        let board = try StoryboardBuilder.build(script: script, preset: preset, duration: 15)
        let cues = CaptionSplitter.cues(from: script, duration: 15, maxWordsPerCard: 5, storyboard: board)
        XCTAssertTrue(CaptionSplitter.overlappingPairs(cues).isEmpty)
        XCTAssertTrue(cues[0].text.contains("Stop"))
        XCTAssertFalse(cues[0].text.contains("Morning"))
        XCTAssertGreaterThanOrEqual(cues[0].duration, 1.48)
    }
}

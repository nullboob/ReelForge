import XCTest
@testable import ReelForgeCore

final class PublishPackTests: XCTestCase {
    func testTitleStaysUnder70AndHasChapters() throws {
        let dir = try XCTUnwrap(PresetCatalog.bundledDirectory() ?? PresetCatalog.sourceTreeDirectory())
        let preset = try PresetCatalog.load(from: dir).first { $0.id == "listicle" }!
        let script = ScriptWriter.write(topic: "7 ways to start a faceless channel", presetID: preset.id, durationSec: 45)
        let board = StoryboardBuilder.build(script: script, preset: preset, duration: 45)
        let pack = PublishPackWriter.write(
            topic: "7 ways to start a faceless channel",
            script: script,
            storyboard: board,
            preset: preset,
            channel: ChannelKit(name: "Night Desk"),
            series: "Beginner YouTube",
            target: .short
        )
        XCTAssertLessThanOrEqual(pack.title.count, 70)
        XCTAssertFalse(pack.description.isEmpty)
        XCTAssertFalse(pack.tags.isEmpty)
        XCTAssertEqual(pack.chapters.count, board.beats.count)
        XCTAssertTrue(pack.suggestedFilename.hasSuffix(".mp4"))
        XCTAssertTrue(pack.description.contains("0:00") || pack.chapters.first?.timestamp == "0:00")
    }

    func testSRTCoversCues() {
        let cues = CaptionSplitter.align(text: "one two three four", duration: 4, maxWordsPerCard: 2)
        let srt = SRTWriter.string(from: cues)
        XCTAssertTrue(srt.contains("-->"))
        XCTAssertTrue(srt.contains("one two"))
        XCTAssertTrue(srt.hasPrefix("1\n"))
    }

    func testFourteenPresetsLoad() throws {
        let dir = try XCTUnwrap(PresetCatalog.bundledDirectory() ?? PresetCatalog.sourceTreeDirectory())
        let presets = try PresetCatalog.load(from: dir)
        XCTAssertEqual(presets.count, 14)
        XCTAssertTrue(presets.contains { $0.id == "podcast-clip" })
        XCTAssertTrue(presets.contains { $0.id == "news-roundup" })
    }
}

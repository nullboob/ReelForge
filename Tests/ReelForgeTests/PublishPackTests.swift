import XCTest
@testable import ReelForgeCore

final class PublishPackTests: XCTestCase {
    func testTitleStaysUnder70AndHasChapters() throws {
        let dir = try XCTUnwrap(PresetCatalog.bundledDirectory() ?? PresetCatalog.sourceTreeDirectory())
        let preset = try PresetCatalog.load(from: dir).first { $0.id == "listicle" }!
        let script = ScriptWriter.write(topic: "7 ways to start a faceless channel", presetID: preset.id, durationSec: 45)
        let board = try StoryboardBuilder.build(script: script, preset: preset, duration: 45)
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
        XCTAssertEqual(pack.chapters.first?.timestamp, "0:00")
        let first150 = String(pack.description.prefix(150))
        XCTAssertTrue(first150.contains(String(script.hook.prefix(20))))
        XCTAssertTrue(pack.description.lowercased().contains("synthetic") || pack.syntheticReminder.lowercased().contains("synthetic"))
    }

    func testSRTCoversCues() {
        let cues = CaptionSplitter.align(text: "one two three four", duration: 4, maxWordsPerCard: 2)
        let srt = SRTWriter.string(from: cues)
        XCTAssertTrue(srt.contains("-->"))
        XCTAssertTrue(srt.contains("one two"))
        XCTAssertTrue(srt.hasPrefix("1\n"))
    }

    func testThumbnailHeadlineStaysFourToSixWords() {
        let long = "Stop scrolling. Your morning walk is about to make the usual advice look expensive and tired."
        let line = PublishPackWriter.thumbnailHeadline(from: long)
        let count = line.split { $0.isWhitespace }.count
        XCTAssertGreaterThanOrEqual(count, 3)
        XCTAssertLessThanOrEqual(count, 6)
        XCTAssertFalse(line.lowercased().hasPrefix("in this video"))
    }

    func testCaptionSafeAreaClearsShortsChrome() {
        let safe = CaptionSafeArea.rect(width: 1080, height: 1920)
        XCTAssertGreaterThanOrEqual(safe.y / 1920, 0.17)
        XCTAssertGreaterThanOrEqual((1920 - (safe.y + safe.height)) / 1920, 0.11)
        XCTAssertLessThanOrEqual((safe.x + safe.width) / 1080, 0.83)
        XCTAssertEqual(CaptionSafeArea.maxWords(forPresetID: "viral-hook", requested: 12), 3)
        XCTAssertEqual(CaptionSafeArea.maxWords(forPresetID: "viral-hook", requested: 2), 2)
    }

    func testMusicDuckStaysEightToTwelveDb() {
        let quiet = MusicStyle(mood: .pulse, bpm: 120, duckDb: -20)
        let loud = MusicStyle(mood: .pulse, bpm: 120, duckDb: -4)
        let mid = MusicStyle(mood: .pulse, bpm: 120, duckDb: -10)
        XCTAssertEqual(quiet.clampedDuckDb, -12, accuracy: 0.001)
        XCTAssertEqual(loud.clampedDuckDb, -8, accuracy: 0.001)
        XCTAssertEqual(mid.clampedDuckDb, -10, accuracy: 0.001)
        XCTAssertGreaterThan(quiet.duckLinear, 0)
        XCTAssertLessThan(quiet.duckLinear, loud.duckLinear)
    }

    func testStockQuerySkipsGenericFirstPage() {
        let rewritten = StockQueryHygiene.specificQuery("office handshake")
        XCTAssertTrue(rewritten.contains("handheld"))
        XCTAssertNotEqual(rewritten, "office handshake")
        XCTAssertTrue(StockQueryHygiene.specificQuery("rainy alley neon").contains("rainy"))
    }

    func testHookRulesRejectGreetingOpens() {
        XCTAssertTrue(HookRules.isForbiddenOpen("Welcome back to the channel"))
        XCTAssertTrue(HookRules.isForbiddenOpen("In this video we discuss walking"))
        XCTAssertFalse(HookRules.isForbiddenOpen("Stop scrolling. Your walk wins."))
    }

    func testFourteenPresetsLoad() throws {
        let dir = try XCTUnwrap(PresetCatalog.bundledDirectory() ?? PresetCatalog.sourceTreeDirectory())
        let presets = try PresetCatalog.load(from: dir)
        XCTAssertEqual(presets.count, 14)
        XCTAssertTrue(presets.contains { $0.id == "podcast-clip" })
        XCTAssertTrue(presets.contains { $0.id == "news-roundup" })
    }
}

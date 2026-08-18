import XCTest
@testable import ReelForgeCore

final class TimelinePlanTests: XCTestCase {
    func testHardCutHasNoOverlap() throws {
        let plan = try plan(presetID: "viral-hook", duration: 15)
        XCTAssertEqual(plan.transition, .hardCut)
        XCTAssertEqual(plan.overlap, 0)
        XCTAssertEqual(plan.clips.count, plan.clips.map(\.beatID).count)
        for pair in zip(plan.clips, plan.clips.dropFirst()) {
            XCTAssertEqual(pair.0.end, pair.1.start, accuracy: 0.001)
        }
        XCTAssertEqual(plan.width, 1080)
        XCTAssertEqual(plan.height, 1920)
    }

    func testFadeIntroducesOverlap() throws {
        let plan = try plan(presetID: "cinematic-story", duration: 30)
        XCTAssertEqual(plan.transition, .fade)
        XCTAssertGreaterThan(plan.overlap, 0)
        if plan.clips.count >= 2 {
            XCTAssertLessThan(plan.clips[1].start, plan.clips[0].end)
        }
    }

    func testDimensionsFollowAspectOverride() throws {
        let dir = try XCTUnwrap(PresetCatalog.bundledDirectory() ?? PresetCatalog.sourceTreeDirectory())
        let preset = try PresetCatalog.load(from: dir).first { $0.id == "product-demo" }!
        XCTAssertEqual(preset.aspect, .landscape)
        let script = ScriptWriter.write(topic: "a calmer editor", presetID: preset.id)
        let board = try StoryboardBuilder.build(script: script, preset: preset, duration: 30)
        let plan = TimelinePlanner.plan(
            storyboard: board,
            preset: preset,
            aspect: .square,
            assetsByBeat: [:],
            captions: [],
            voicePath: "voice.wav",
            voiceDuration: 30,
            musicPath: "music.wav",
            musicVolume: 0.16
        )
        XCTAssertEqual(plan.width, 1080)
        XCTAssertEqual(plan.height, 1080)
        XCTAssertNotNil(plan.voice)
        XCTAssertNotNil(plan.music)
        XCTAssertEqual(plan.clips.count, board.beats.count)
    }

    func testMusicBedWritesValidWAVHeader() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("reelforge-bed.wav")
        try? FileManager.default.removeItem(at: url)
        try MusicBedSynthesizer.writeLoop(mood: .pulse, bpm: 128, to: url)
        let data = try Data(contentsOf: url)
        XCTAssertGreaterThan(data.count, 1000)
        XCTAssertEqual(String(data: data.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: data.subdata(in: 8..<12), encoding: .ascii), "WAVE")
    }

    private func plan(presetID: String, duration: Double) throws -> TimelinePlan {
        let dir = try XCTUnwrap(PresetCatalog.bundledDirectory() ?? PresetCatalog.sourceTreeDirectory())
        let preset = try PresetCatalog.load(from: dir).first { $0.id == presetID }!
        let script = ScriptWriter.write(topic: "3 reasons your morning walk beats the gym", presetID: preset.id)
        let board = try StoryboardBuilder.build(script: script, preset: preset, duration: duration)
        return TimelinePlanner.plan(
            storyboard: board,
            preset: preset,
            aspect: preset.aspect,
            assetsByBeat: [:],
            captions: CaptionSplitter.cues(from: script, duration: duration, maxWordsPerCard: preset.captionStyle.maxWordsPerCard, storyboard: board),
            voicePath: nil,
            voiceDuration: nil,
            musicPath: nil,
            musicVolume: 0.2
        )
    }
}

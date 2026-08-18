import XCTest
@testable import ReelForgeCore

final class StoryboardTimingTests: XCTestCase {
    func testBeatsSumToTargetDuration() throws {
        let preset = try viral()
        let script = ScriptWriter.write(topic: "3 reasons your morning walk beats the gym", presetID: preset.id)
        let board = StoryboardBuilder.build(script: script, preset: preset, duration: Double(preset.durationSec))
        XCTAssertEqual(board.duration, Double(preset.durationSec), accuracy: 0.08)
        let sum = board.beats.reduce(0.0) { $0 + $1.duration }
        XCTAssertEqual(sum, board.duration, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(board.beats.count, 3)
    }

    func testInteriorCutsStayNearPaceRange() throws {
        let preset = try viral()
        let script = ScriptWriter.write(topic: "5 ways to ship a video tonight", presetID: preset.id)
        let board = StoryboardBuilder.build(script: script, preset: preset, duration: 15)
        let interior = board.beats.dropFirst().dropLast()
        for beat in interior {
            XCTAssertGreaterThan(beat.duration, 0.35, beat.text)
            XCTAssertLessThan(beat.duration, 3.5, beat.text)
        }
    }

    func testRescaleChangesDurationButKeepsOrder() throws {
        let preset = try cinematic()
        let script = ScriptWriter.write(topic: "a quiet road at dusk", presetID: preset.id)
        let board = StoryboardBuilder.build(script: script, preset: preset, duration: 45)
        let scaled = StoryboardBuilder.rescale(board, to: 22)
        XCTAssertEqual(scaled.duration, 22, accuracy: 0.05)
        XCTAssertEqual(scaled.beats.count, board.beats.count)
        XCTAssertEqual(scaled.beats.first?.role, board.beats.first?.role)
        for window in zip(scaled.beats, scaled.beats.dropFirst()) {
            XCTAssertEqual(window.0.end, window.1.start, accuracy: 0.0001)
        }
    }

    func testFirstHookBeatHoldsAtLeast1_5Seconds() throws {
        let preset = try viral()
        let script = ScriptWriter.write(topic: "3 reasons your morning walk beats the gym", presetID: preset.id)
        let board = StoryboardBuilder.build(script: script, preset: preset, duration: 15)
        let hook = try XCTUnwrap(board.beats.first)
        XCTAssertEqual(hook.role, .hook)
        XCTAssertGreaterThanOrEqual(hook.duration, 1.5 - 0.02)
        XCTAssertEqual(board.duration, 15, accuracy: 0.08)
    }

    func testSplitsStayOnPhraseBoundaries() throws {
        let preset = try viral()
        let script = GeneratedScript(
            hook: "Stop scrolling now.",
            body: ["Then a full stop ends the thought. After that we continue with the second phrase."],
            cta: "Follow along.",
            source: .template
        )
        let board = StoryboardBuilder.build(script: script, preset: preset, duration: 15)
        let texts = board.beats.map(\.text)
        XCTAssertFalse(texts.contains { $0.hasPrefix("stop ends") || $0.hasPrefix("that we") })
        XCTAssertTrue(texts.contains { $0.contains("full stop") || $0.contains("After that") })
    }

    func testTutorialBeatsCarryStepNumbers() throws {
        let preset = try load("tutorial-steps")
        let script = ScriptWriter.write(topic: "4 steps to cut a reel", presetID: preset.id)
        let board = StoryboardBuilder.build(script: script, preset: preset, duration: 45)
        XCTAssertTrue(board.beats.contains { $0.stepNumber != nil })
    }

    private func viral() throws -> Preset { try load("viral-hook") }
    private func cinematic() throws -> Preset { try load("cinematic-story") }

    private func load(_ id: String) throws -> Preset {
        let dir = try XCTUnwrap(PresetCatalog.bundledDirectory() ?? PresetCatalog.sourceTreeDirectory())
        return try PresetCatalog.load(from: dir).first { $0.id == id }!
    }
}

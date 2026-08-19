import XCTest
@testable import ReelForgeCore

final class FootageLadderTests: XCTestCase {
    func testFastAndStockFirstUseLTXOnlyOnHook() {
        XCTAssertEqual(FootageLadder.kind(beatIndex: 0, mode: .localFast), .ltx)
        XCTAssertEqual(FootageLadder.kind(beatIndex: 1, mode: .localFast), .qwen)
        XCTAssertEqual(FootageLadder.kind(beatIndex: 8, mode: .localFast), .qwen)
        XCTAssertEqual(FootageLadder.kind(beatIndex: 0, mode: .stockFirst), .ltx)
        XCTAssertEqual(FootageLadder.kind(beatIndex: 2, mode: .stockFirst), .qwen)
        XCTAssertTrue(FootageLadder.stockBeforeLocal(.stockFirst))
        XCTAssertFalse(FootageLadder.stockBeforeLocal(.localFast))
    }

    func testQualityUsesWanForHookAndTwoBodyBeats() {
        XCTAssertEqual(FootageLadder.kind(beatIndex: 0, mode: .localQuality), .wan)
        XCTAssertEqual(FootageLadder.kind(beatIndex: 1, mode: .localQuality), .wan)
        XCTAssertEqual(FootageLadder.kind(beatIndex: 2, mode: .localQuality), .wan)
        XCTAssertEqual(FootageLadder.kind(beatIndex: 3, mode: .localQuality), .qwen)
    }

    func testTimeoutsAndCredits() {
        XCTAssertEqual(FootageLadder.timeoutSeconds(for: .ltx), 90)
        XCTAssertEqual(FootageLadder.timeoutSeconds(for: .wan), 180)
        XCTAssertEqual(FootageLadder.timeoutSeconds(for: .qwen), 20)
        XCTAssertEqual(FootageLadder.credit(for: .ltx), "LTX-2.3 local")
        XCTAssertEqual(FootageLadder.credit(for: .wan), "Wan 2.2 local")
        XCTAssertEqual(FootageLadder.credit(for: .qwen), "Qwen Image local")
        XCTAssertEqual(FootageLadder.clampClipSeconds(1), 2)
        XCTAssertEqual(FootageLadder.clampClipSeconds(9), 4)
    }

    func testPromptBansGenericOfficeAndForcesNineSixteen() {
        let prompt = FootageLadder.renderPrompt(text: "Your morning walk wins", styleSuffix: "photoreal dusk")
        XCTAssertTrue(prompt.contains("9:16"))
        XCTAssertTrue(prompt.contains("no text"))
        XCTAssertTrue(prompt.contains("no logo"))
        XCTAssertTrue(prompt.contains("photoreal dusk"))
        XCTAssertTrue(prompt.lowercased().contains("morning walk"))
    }

    func testFillTemplateKeepsIntegerTokens() throws {
        let raw = try ComfyWorkflows.load("ltx-fast")
        let filled = ComfyWorkflows.fillTemplate(raw, mapping: [
            "PROMPT": "walk",
            "NEGATIVE": "text",
            "WIDTH": 1088,
            "HEIGHT": 1920,
            "FRAMES": 49,
            "SEED": 7,
            "CKPT": "ltx-2.3-22b-distilled.safetensors",
            "LORA": "ltx-2.3-22b-distilled-lora-384.safetensors"
        ])
        let graph = filled as? [String: Any]
        let sampler = graph?["5"] as? [String: Any]
        let inputs = sampler?["inputs"] as? [String: Any]
        XCTAssertEqual(inputs?["width"] as? Int, 1088)
        XCTAssertEqual(inputs?["length"] as? Int, 49)
    }
}

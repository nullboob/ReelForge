import XCTest
@testable import ReelForgeCore

final class ScriptWriterTests: XCTestCase {
    func testListTopicProducesCountedBody() {
        let script = ScriptWriter.write(
            topic: "3 reasons your morning walk beats the gym",
            presetID: "viral-hook"
        )
        XCTAssertEqual(script.body.count, 3)
        XCTAssertFalse(script.hook.isEmpty)
        XCTAssertFalse(script.cta.isEmpty)
        XCTAssertTrue(script.fullText.lowercased().contains("walk") || script.hook.lowercased().contains("walk"))
        XCTAssertEqual(script.source, .template)
    }

    func testEveryPresetWritesHookBodyCTA() {
        for id in PresetCatalog.expectedIDs {
            let script = ScriptWriter.write(topic: "morning walk beats the gym", presetID: id)
            XCTAssertFalse(script.hook.isEmpty, id)
            XCTAssertFalse(script.body.isEmpty, id)
            XCTAssertFalse(script.cta.isEmpty, id)
            XCTAssertGreaterThan(script.fullText.count, 40, id)
        }
    }

    func testUserScriptIsParsedNotRewritten() {
        let text = """
        Stay with me for ten seconds.
        The first idea is walking before coffee.
        The second idea is leaving the phone at home.
        Go try it tomorrow morning.
        """
        XCTAssertTrue(ScriptWriter.looksLikeFullScript(text))
        let script = ScriptWriter.parseUserScript(text)
        XCTAssertEqual(script.source, .user)
        XCTAssertTrue(script.hook.lowercased().contains("stay with me"))
        XCTAssertEqual(script.body.count, 2)
        XCTAssertTrue(script.cta.lowercased().contains("tomorrow"))
    }

    func testOllamaParseFallsBackWhenEmpty() {
        let parsed = ScriptWriter.parseModelOutput("   ", fallbackTopic: "deep work", presetID: "faceless-facts")
        XCTAssertEqual(parsed.source, .template)
        XCTAssertFalse(parsed.fullText.isEmpty)
    }

    func testOllamaLabeledOutput() {
        let raw = """
        HOOK: This is the open.
        BODY: Point one lands first.
        BODY: Point two keeps you here.
        CTA: Follow for the close.
        """
        let parsed = ScriptWriter.parseModelOutput(raw, fallbackTopic: "deep work", presetID: "viral-hook")
        XCTAssertEqual(parsed.source, .ollama)
        XCTAssertTrue(parsed.hook.contains("open"))
        XCTAssertEqual(parsed.body.count, 2)
        XCTAssertTrue(parsed.cta.contains("Follow"))
    }
}

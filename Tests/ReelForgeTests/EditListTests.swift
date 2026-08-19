import XCTest
@testable import ReelForgeCore

final class EditListTests: XCTestCase {
    func testFilterComplexIsOneEncodeSidechainAndPunchIn() {
        let edl = sampleEDL()
        let graph = edl.filterComplex(fontsDir: "/tmp/fonts", burnCaptions: true)
        XCTAssertTrue(graph.contains("sidechaincompress"))
        XCTAssertTrue(graph.contains("ass="))
        XCTAssertTrue(graph.contains("yuv420p"))
        XCTAssertTrue(graph.contains("zoompan"))
        XCTAssertTrue(graph.contains("unsharp"))
        XCTAssertFalse(graph.contains("fade=t=in"))
        XCTAssertFalse(edl.hook.fadeFromBlack)
        XCTAssertGreaterThanOrEqual(edl.hook.punchIn, 1.08)
        XCTAssertLessThanOrEqual(edl.hook.punchIn, 1.15)
        XCTAssertTrue(EditEncoder.whitelist.contains("libx264"))
        XCTAssertEqual(edl.encoder.pixFmt, "yuv420p")
        XCTAssertTrue(edl.audioMaster)
        XCTAssertEqual(edl.duck.speechDb, -18, accuracy: 0.001)
        XCTAssertEqual(edl.duck.gapDb, -8, accuracy: 0.001)
        XCTAssertEqual(edl.duck.mode, "sidechaincompress")
    }

    func testPythonShapedJSONRoundTrip() throws {
        let json = """
        {
          "version": 1,
          "width": 1080,
          "height": 1920,
          "fps": 30,
          "duration": 8,
          "audioMaster": true,
          "voice": {"path": "voice.wav", "start": 0, "duration": 8},
          "music": {"path": "music.wav", "start": 0, "duration": 8},
          "duck": {"gapDb": -8, "speechDb": -18, "mode": "sidechaincompress"},
          "captions": {"assPath": "captions.ass", "renderer": "ass", "styleID": "tiktok-classic-outline"},
          "grade": {"contrast": 1.08, "saturation": 1.12, "warmth": 0, "vignette": 0.35, "unsharp": true, "grain": false},
          "hook": {"punchIn": 1.12, "holdSec": 1.5, "flashFrames": 0, "fadeFromBlack": true},
          "clips": [{
            "beatID": "b0",
            "role": "hook",
            "start": 0,
            "duration": 2,
            "source": "hook.mp4",
            "kind": "video",
            "sourceID": "1",
            "kenBurns": false,
            "zoomPulse": false,
            "punchIn": 1.12,
            "transitionIn": "hardCut"
          }],
          "encoder": {
            "preferred": ["h264_nvenc", "h264_qsv", "h264_amf", "h264_videotoolbox", "libx264"],
            "pixFmt": "yuv420p",
            "faststart": true
          }
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(EditList.self, from: json)
        XCTAssertEqual(decoded.width, 1080)
        XCTAssertEqual(decoded.height, 1920)
        XCTAssertFalse(decoded.hook.fadeFromBlack)
        XCTAssertEqual(decoded.clips[0].transitionIn, "hardCut")
        XCTAssertTrue(decoded.encoder.preferred.contains("libx264"))
        let encoded = try decoded.jsonData()
        let again = try JSONDecoder().decode(EditList.self, from: encoded)
        XCTAssertEqual(again.duck.mode, "sidechaincompress")
        XCTAssertEqual(again.clips[0].role, "hook")
    }

    func testForceAlignKeepsScriptTokens() {
        let cues = CaptionSplitter.align(text: "Stop scrolling now", duration: 1.5, maxWordsPerCard: 4)
        let timed = [
            WordTiming(word: "uh", start: 0.0, duration: 0.1),
            WordTiming(word: "stop", start: 0.12, duration: 0.2),
            WordTiming(word: "scrolling", start: 0.35, duration: 0.4),
            WordTiming(word: "now", start: 0.8, duration: 0.3),
            WordTiming(word: "like", start: 1.2, duration: 0.2)
        ]
        let aligned = CaptionSplitter.forceAlign(cues, timed: timed)
        let words = aligned.flatMap { $0.words.map(\.word) }
        XCTAssertEqual(words, ["Stop", "scrolling", "now"])
        XCTAssertFalse(aligned.contains { $0.text.lowercased().contains("uh") || $0.text.lowercased().contains("like") })
        XCTAssertEqual(aligned[0].words[0].start, 0.12, accuracy: 0.001)
    }

    func testUniqueSourceDoesNotReplayUsedID() {
        XCTAssertEqual(StockQueryHygiene.firstUnusedID(ids: [11, 22, 33], excluding: [11, 22]), 33)
        XCTAssertNil(StockQueryHygiene.firstUnusedID(ids: [11], excluding: [11]))
        XCTAssertNil(StockQueryHygiene.firstUnusedID(ids: [0], excluding: []))
    }

    private func sampleEDL() -> EditList {
        EditList.make(
            beats: [
                Beat(id: "b0", index: 0, role: .hook, text: "Stop scrolling", start: 0, duration: 2, unsplashQuery: "walk"),
                Beat(id: "b1", index: 1, role: .body(0), text: "Daylight is free", start: 2, duration: 3, unsplashQuery: "sun")
            ],
            sources: [
                "b0": ("hook.mp4", "video", "pexels-1"),
                "b1": ("body.png", "image", "qwen-1")
            ],
            voicePath: "voice.wav",
            musicPath: "music.wav",
            duration: 5,
            width: 1080,
            height: 1920,
            grade: ColorGrade(contrast: 1.08, saturation: 1.12, warmth: 0.2, vignette: 0.35),
            grain: false,
            kenBurns: true,
            zoomPulse: true,
            assPath: "captions.ass",
            captionStyleID: "tiktok-classic-outline",
            captionRenderer: "ass"
        )
    }
}

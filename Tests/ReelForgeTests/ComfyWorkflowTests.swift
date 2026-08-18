import XCTest
@testable import ReelForgeCore

final class ComfyWorkflowTests: XCTestCase {
    func testDetectsStandardT2IAndLTX() {
        let info: [String: Any] = [
            "CheckpointLoaderSimple": [
                "input": ["required": ["ckpt_name": [["qwen-image-edit.safetensors", "sdxl.safetensors"]]]]
            ],
            "CLIPTextEncode": [:],
            "KSampler": [
                "input": ["required": [
                    "sampler_name": [["euler", "dpmpp_2m"]],
                    "scheduler": [["normal", "karras"]]
                ]]
            ],
            "EmptyLatentImage": [:],
            "VAEDecode": [:],
            "SaveImage": [:],
            "LTXVImgToVideo": [:],
            "TextEncodeQwenImageEdit": [:]
        ]
        let caps = ComfyWorkflowBuilder.capabilities(objectInfo: info, online: true)
        XCTAssertTrue(caps.online)
        XCTAssertTrue(caps.canTextToImage)
        XCTAssertTrue(caps.canImageToVideo)
        XCTAssertTrue(caps.hasLTX)
        XCTAssertTrue(caps.hasQwenImage)
        XCTAssertEqual(caps.checkpoint, "qwen-image-edit.safetensors")
        XCTAssertEqual(caps.sampler, "euler")
    }

    func testMissingSamplerMeansNoBuiltinT2I() {
        let info: [String: Any] = [
            "CheckpointLoaderSimple": [
                "input": ["required": ["ckpt_name": [["ltx-video-2b.safetensors"]]]]
            ],
            "LTXVImgToVideo": [:]
        ]
        let caps = ComfyWorkflowBuilder.capabilities(objectInfo: info, online: true)
        XCTAssertFalse(caps.canTextToImage)
        XCTAssertTrue(caps.canImageToVideo)
        XCTAssertNil(ComfyWorkflowBuilder.textToImagePrompt(text: "hello", width: 1080, height: 1920, capabilities: caps))
    }

    func testBuiltGraphCarriesPromptAndAlignedSize() {
        var caps = ComfyCapabilities(online: true, canTextToImage: true)
        caps.checkpoint = "model.safetensors"
        caps.sampler = "euler"
        caps.scheduler = "normal"
        let graph = ComfyWorkflowBuilder.textToImagePrompt(
            text: "morning walk, cinematic",
            width: 1080,
            height: 1920,
            capabilities: caps
        )
        XCTAssertNotNil(graph)
        let encode = graph?["6"] as? [String: Any]
        let inputs = encode?["inputs"] as? [String: Any]
        XCTAssertEqual(inputs?["text"] as? String, "morning walk, cinematic")
        let latent = (graph?["5"] as? [String: Any])?["inputs"] as? [String: Any]
        XCTAssertEqual(latent?["width"] as? Int, 768)
        XCTAssertEqual((latent?["height"] as? Int ?? 0) % 8, 0)
    }

    func testInjectsPromptAndImageIntoUserWorkflow() {
        let raw: [String: Any] = [
            "10": [
                "class_type": "CLIPTextEncode",
                "inputs": ["text": "placeholder"]
            ],
            "11": [
                "class_type": "LoadImage",
                "inputs": ["image": "old.png"]
            ]
        ]
        let injected = ComfyWorkflowBuilder.inject(into: raw, prompt: "hook beat", imageFilename: "reel.png")
        let text = ((injected["10"] as? [String: Any])?["inputs"] as? [String: Any])?["text"] as? String
        let image = ((injected["11"] as? [String: Any])?["inputs"] as? [String: Any])?["image"] as? String
        XCTAssertEqual(text, "hook beat")
        XCTAssertEqual(image, "reel.png")
    }

    func testHistoryPicksFirstImage() {
        let history: [String: Any] = [
            "outputs": [
                "9": [
                    "images": [[
                        "filename": "ReelForge_00001.png",
                        "subfolder": "",
                        "type": "output"
                    ]]
                ]
            ]
        ]
        let file = ComfyWorkflowBuilder.firstOutputFile(from: history)
        XCTAssertEqual(file?.filename, "ReelForge_00001.png")
        XCTAssertEqual(file?.type, "output")
    }
}

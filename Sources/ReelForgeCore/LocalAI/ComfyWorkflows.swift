import Foundation

public enum ComfyWorkflows {
    public static let defaultURL = "http://127.0.0.1:8188"
    public static let negative = "text, words, letters, logo, watermark, caption, subtitle, title card, office, handshake, aerial city, stock footage, generic"
    public static let defaultModels: [String: String] = [
        "ltxCkpt": "ltx-2.3-22b-distilled.safetensors",
        "ltxLora": "ltx-2.3-22b-distilled-lora-384.safetensors",
        "ltxFallback": "ltx-video-2b-v0.9.safetensors",
        "qwenCkpt": "qwen_image_fp8_e4m3fn.safetensors",
        "qwenLora": "Qwen-Image-Lightning-8steps-V1.0.safetensors",
        "qwenClip": "qwen_2.5_vl_7b_fp8_scaled.safetensors",
        "qwenVae": "qwen_image_vae.safetensors",
        "qwenEditCkpt": "qwen_image_edit_2511.safetensors",
        "qwenEditLora": "Qwen-Image-Edit-Lightning-4steps-V1.0.safetensors",
        "wanCkpt": "wan2.2_t2v_low_noise_14B_fp8_scaled.safetensors",
        "wanLora": "lightx2v_T2V_14B_cfg_step_distill_v2.safetensors",
        "wanClip": "umt5_xxl_fp8_e4m3fn_scaled.safetensors",
        "wanVae": "wan_2.1_vae.safetensors",
        "ideogramCkpt": "ideogram4_fp8.safetensors"
    ]

    public static func fillTemplate(_ node: Any, mapping: [String: Any]) -> Any {
        if let text = node as? String {
            for (key, value) in mapping {
                let token = "{{\(key)}}"
                if text == token {
                    return value
                }
            }
            var out = text
            for (key, value) in mapping {
                out = out.replacingOccurrences(of: "{{\(key)}}", with: "\(value)")
            }
            return out
        }
        if let array = node as? [Any] {
            return array.map { fillTemplate($0, mapping: mapping) }
        }
        if let dict = node as? [String: Any] {
            return dict.mapValues { fillTemplate($0, mapping: mapping) }
        }
        if let dict = node as? NSDictionary {
            var next: [String: Any] = [:]
            for (key, value) in dict {
                next["\(key)"] = fillTemplate(value, mapping: mapping)
            }
            return next
        }
        if let array = node as? NSArray {
            return array.map { fillTemplate($0, mapping: mapping) }
        }
        return node
    }

    public static func load(_ name: String) throws -> [String: Any] {
        let data = try loadData(named: name)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dict = object as? [String: Any] else {
            throw NSError(domain: "ComfyWorkflows", code: 1, userInfo: [NSLocalizedDescriptionKey: "Workflow \(name) is not an object"])
        }
        return dict
    }

    public static func loadData(named name: String) throws -> Data {
        let file = "\(name).json"
        if let override = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let path = override.appendingPathComponent("ReelForge/workflows/\(file)")
            if FileManager.default.fileExists(atPath: path.path) {
                return try Data(contentsOf: path)
            }
        }
        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "workflows") {
            return try Data(contentsOf: url)
        }
        #else
        if let url = Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "workflows") {
            return try Data(contentsOf: url)
        }
        #endif
        if let embedded = embeddedJSON[name] {
            return Data(embedded.utf8)
        }
        throw NSError(domain: "ComfyWorkflows", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing workflow \(name)"])
    }

    private static let embeddedJSON: [String: String] = [
        "ltx-fast": """
        {"1":{"class_type":"CheckpointLoaderSimple","inputs":{"ckpt_name":"{{CKPT}}"}},"2":{"class_type":"LoraLoaderModelOnly","inputs":{"model":["1",0],"lora_name":"{{LORA}}","strength_model":1.0}},"3":{"class_type":"CLIPTextEncode","inputs":{"text":"{{PROMPT}}","clip":["1",1]}},"4":{"class_type":"CLIPTextEncode","inputs":{"text":"{{NEGATIVE}}","clip":["1",1]}},"5":{"class_type":"EmptyLTXVLatentVideo","inputs":{"width":"{{WIDTH}}","height":"{{HEIGHT}}","length":"{{FRAMES}}","batch_size":1}},"6":{"class_type":"LTXVConditioning","inputs":{"positive":["3",0],"negative":["4",0],"frame_rate":24}},"7":{"class_type":"KSampler","inputs":{"seed":"{{SEED}}","steps":8,"cfg":1,"sampler_name":"euler","scheduler":"simple","denoise":1,"model":["2",0],"positive":["6",0],"negative":["6",1],"latent_image":["5",0]}},"8":{"class_type":"VAEDecode","inputs":{"samples":["7",0],"vae":["1",2]}},"9":{"class_type":"SaveVideo","inputs":{"filename_prefix":"reelforge-ltx","images":["8",0],"fps":24,"format":"mp4"}}}
        """,
        "wan-quality": """
        {"1":{"class_type":"UNETLoader","inputs":{"unet_name":"{{CKPT}}","weight_dtype":"fp8_e4m3fn"}},"2":{"class_type":"LoraLoaderModelOnly","inputs":{"model":["1",0],"lora_name":"{{LORA}}","strength_model":1.0}},"3":{"class_type":"CLIPLoader","inputs":{"clip_name":"{{CLIP}}","type":"wan"}},"4":{"class_type":"VAELoader","inputs":{"vae_name":"{{VAE}}"}},"5":{"class_type":"CLIPTextEncode","inputs":{"text":"{{PROMPT}}","clip":["3",0]}},"6":{"class_type":"CLIPTextEncode","inputs":{"text":"{{NEGATIVE}}","clip":["3",0]}},"7":{"class_type":"EmptyHunyuanLatentVideo","inputs":{"width":"{{WIDTH}}","height":"{{HEIGHT}}","length":"{{FRAMES}}","batch_size":1}},"8":{"class_type":"KSampler","inputs":{"seed":"{{SEED}}","steps":4,"cfg":1,"sampler_name":"euler","scheduler":"simple","denoise":1,"model":["2",0],"positive":["5",0],"negative":["6",0],"latent_image":["7",0]}},"9":{"class_type":"VAEDecode","inputs":{"samples":["8",0],"vae":["4",0]}},"10":{"class_type":"SaveVideo","inputs":{"filename_prefix":"reelforge-wan","images":["9",0],"fps":16,"format":"mp4"}}}
        """,
        "qwen-image": """
        {"1":{"class_type":"UNETLoader","inputs":{"unet_name":"{{CKPT}}","weight_dtype":"fp8_e4m3fn"}},"2":{"class_type":"LoraLoaderModelOnly","inputs":{"model":["1",0],"lora_name":"{{LORA}}","strength_model":1.0}},"3":{"class_type":"CLIPLoader","inputs":{"clip_name":"{{CLIP}}","type":"qwen_image"}},"4":{"class_type":"VAELoader","inputs":{"vae_name":"{{VAE}}"}},"5":{"class_type":"CLIPTextEncode","inputs":{"text":"{{PROMPT}}","clip":["3",0]}},"6":{"class_type":"CLIPTextEncode","inputs":{"text":"{{NEGATIVE}}","clip":["3",0]}},"7":{"class_type":"EmptyLatentImage","inputs":{"width":"{{WIDTH}}","height":"{{HEIGHT}}","batch_size":1}},"8":{"class_type":"KSampler","inputs":{"seed":"{{SEED}}","steps":8,"cfg":1,"sampler_name":"euler","scheduler":"simple","denoise":1,"model":["2",0],"positive":["5",0],"negative":["6",0],"latent_image":["7",0]}},"9":{"class_type":"VAEDecode","inputs":{"samples":["8",0],"vae":["4",0]}},"10":{"class_type":"SaveImage","inputs":{"filename_prefix":"reelforge-qwen","images":["9",0]}}}
        """
    ]
}

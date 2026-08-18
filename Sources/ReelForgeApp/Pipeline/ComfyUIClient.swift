import Foundation

actor ComfyUIClient {
    static let shared = ComfyUIClient()
    static let baseURL = URL(string: ComfyWorkflowBuilder.defaultBaseURL)!

    private var cachedCaps: ComfyCapabilities?

    func capabilities(force: Bool = false) async -> ComfyCapabilities {
        if !force, let cachedCaps { return cachedCaps }
        guard let stats = URL(string: "http://127.0.0.1:8188/system_stats") else {
            return ComfyCapabilities()
        }
        var request = URLRequest(url: stats)
        request.timeoutInterval = 0.8
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<500).contains(http.statusCode)
        else {
            cachedCaps = ComfyCapabilities()
            return ComfyCapabilities()
        }

        var info: [String: Any] = [:]
        if let objectURL = URL(string: "http://127.0.0.1:8188/object_info"),
           let (data, objResponse) = try? await URLSession.shared.data(from: objectURL),
           let http = objResponse as? HTTPURLResponse, http.statusCode == 200,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            info = json
        }
        var caps = ComfyWorkflowBuilder.capabilities(objectInfo: info, online: true)
        if loadWorkflow(named: "comfy-i2v.json") != nil {
            caps.canImageToVideo = true
            if !caps.detail.contains("I2V") {
                caps.detail += caps.detail.isEmpty ? "user I2V workflow" : " · user I2V workflow"
            }
        }
        if loadWorkflow(named: "comfy-t2i.json") != nil {
            caps.canTextToImage = true
        }
        cachedCaps = caps
        return caps
    }

    func generateImage(prompt: String, size: (Int, Int), to url: URL) async -> Bool {
        let caps = await capabilities()
        guard caps.online else { return false }
        if let graph = ComfyWorkflowBuilder.textToImagePrompt(
            text: prompt,
            width: size.0,
            height: size.1,
            capabilities: caps
        ) {
            if await queueAndDownload(graph: graph, to: url, kinds: ["images"]) {
                return true
            }
        }
        if var workflow = loadWorkflow(named: "comfy-t2i.json") {
            workflow = ComfyWorkflowBuilder.inject(into: workflow, prompt: prompt, imageFilename: nil)
            if await queueAndDownload(graph: workflow, to: url, kinds: ["images"]) {
                return true
            }
        }
        return false
    }

    func generateVideo(prompt: String, startImage: URL?, to url: URL) async -> Bool {
        let caps = await capabilities()
        guard caps.online, caps.canImageToVideo else { return false }
        guard var workflow = loadWorkflow(named: "comfy-i2v.json") else { return false }
        var uploadedName: String?
        if let startImage {
            uploadedName = await uploadImage(startImage)
        }
        workflow = ComfyWorkflowBuilder.inject(into: workflow, prompt: prompt, imageFilename: uploadedName)
        return await queueAndDownload(graph: workflow, to: url, kinds: ["gifs", "videos", "images"])
    }

    private func queueAndDownload(graph: [String: Any], to url: URL, kinds: [String]) async -> Bool {
        guard let endpoint = URL(string: "http://127.0.0.1:8188/prompt") else { return false }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "client_id": "reelforge",
            "prompt": graph
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["node_errors"] == nil || (json["node_errors"] as? [String: Any])?.isEmpty == true,
              let promptID = json["prompt_id"] as? String
        else { return false }

        guard let file = await waitForOutput(promptID: promptID, kinds: kinds) else { return false }
        return await downloadView(file: file, to: url)
    }

    private func waitForOutput(promptID: String, kinds: [String]) async -> (filename: String, subfolder: String, type: String)? {
        guard let historyURL = URL(string: "http://127.0.0.1:8188/history/\(promptID)") else { return nil }
        for _ in 0..<40 {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard let (data, response) = try? await URLSession.shared.data(from: historyURL),
                  let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            let entry = (json[promptID] as? [String: Any]) ?? json
            if let status = entry["status"] as? [String: Any],
               (status["status_str"] as? String) == "error" {
                return nil
            }
            if let file = ComfyWorkflowBuilder.firstOutputFile(from: entry, kinds: kinds)
                ?? ComfyWorkflowBuilder.firstOutputFile(from: json, kinds: kinds) {
                return file
            }
        }
        return nil
    }

    private func downloadView(file: (filename: String, subfolder: String, type: String), to url: URL) async -> Bool {
        var components = URLComponents(string: "http://127.0.0.1:8188/view")
        components?.queryItems = [
            URLQueryItem(name: "filename", value: file.filename),
            URLQueryItem(name: "subfolder", value: file.subfolder),
            URLQueryItem(name: "type", value: file.type)
        ]
        guard let viewURL = components?.url,
              let (data, response) = try? await URLSession.shared.data(from: viewURL),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              data.count > 80
        else { return false }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
            return true
        } catch {
            return false
        }
    }

    private func uploadImage(_ fileURL: URL) async -> String? {
        guard let endpoint = URL(string: "http://127.0.0.1:8188/upload/image"),
              let bytes = try? Data(contentsOf: fileURL)
        else { return nil }
        let boundary = "ReelForge\(UUID().uuidString)"
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"\(fileURL.lastPathComponent)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(bytes)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode)
        else { return nil }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let name = json["name"] as? String {
            return name
        }
        return fileURL.lastPathComponent
    }

    private func loadWorkflow(named filename: String) -> [String: Any]? {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("ReelForge", isDirectory: true)
            .appendingPathComponent(filename)
        let candidates = [
            appSupport,
            Bundle.main.url(forResource: filename.replacingOccurrences(of: ".json", with: ""), withExtension: "json")
        ].compactMap { $0 }
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            if let data = try? Data(contentsOf: url),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let prompt = json["prompt"] as? [String: Any] { return prompt }
                return json
            }
        }
        return nil
    }
}

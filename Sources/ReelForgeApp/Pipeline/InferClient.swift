import Foundation

/// Official Python APIs (ltx-pipelines / diffusers). Not a ComfyUI client.
enum InferClient {
    static func generateVideo(prompt: String, to url: URL, aspect: String, seconds: Double, modelsDir: String?) -> Bool {
        run(mode: "video", prompt: prompt, dest: url, aspect: aspect, seconds: seconds, modelsDir: modelsDir)
    }

    static func generateImage(prompt: String, to url: URL, aspect: String, modelsDir: String?) -> Bool {
        run(mode: "image", prompt: prompt, dest: url, aspect: aspect, seconds: 0, modelsDir: modelsDir)
    }

    private static func run(mode: String, prompt: String, dest: URL, aspect: String, seconds: Double, modelsDir: String?) -> Bool {
        if ProcessInfo.processInfo.environment["REELFORGE_SKIP_INFER"] == "1" { return false }
        guard let python = pythonExecutable(), let windows = windowsPackageDir() else { return false }
        let process = Process()
        process.executableURL = python
        process.currentDirectoryURL = windows
        var args = ["-m", "reelforge.infer_cli", mode, "--out", dest.path, "--prompt", prompt, "--aspect", aspect]
        if mode == "video" {
            args += ["--seconds", String(seconds)]
        }
        if let modelsDir, !modelsDir.isEmpty {
            args += ["--models-dir", modelsDir]
        }
        process.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PYTHONPATH"] = windows.path
        process.environment = env
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0 && FileManager.default.fileExists(atPath: dest.path)
        } catch {
            return false
        }
    }

    static func pythonExecutable() -> URL? {
        if let override = ProcessInfo.processInfo.environment["REELFORGE_PYTHON"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        for candidate in ["/usr/bin/python3", "/usr/local/bin/python3", "/opt/homebrew/bin/python3"] {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        return nil
    }

    static func windowsPackageDir() -> URL? {
        var url = URL(fileURLWithPath: #file)
        url.deleteLastPathComponent()
        url.deleteLastPathComponent()
        url.deleteLastPathComponent()
        url.deleteLastPathComponent()
        let windows = url.appendingPathComponent("windows")
        if FileManager.default.fileExists(atPath: windows.appendingPathComponent("reelforge").path) {
            return windows
        }
        return nil
    }
}

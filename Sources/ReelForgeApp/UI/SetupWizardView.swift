import AppKit
import SwiftUI

struct SetupWizardView: View {
    @EnvironmentObject private var state: AppState
    @State private var hardware = HardwareSnapshot(nvidia: false, vramGB: 0, appleGPU: true, ramGB: 16, diskFreeGB: 40)
    @State private var recommended: SetupPack = .instant
    @State private var detail = "Detecting this Mac…"
    @State private var busy = false
    @State private var progress: Double = 0
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(SetupWizard.title)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
            Text("The app already works. GPU packs are optional upgrades.")
                .foregroundStyle(RFTheme.muted)
            Text(detail)
                .font(.system(size: 13))
                .foregroundStyle(RFTheme.gold)
            packRow("Instant", "0 GB", "Stock + captions. Always available.", .instant)
            packRow("Fast Image", "~8–12 GB", "Qwen Image Lightning. One click.", .fastImage)
            packRow("Fast Video", "~15–20 GB", "LTX-2.3 distilled GGUF. One click.", .fastVideo)
            if SetupWizard.showQuality(hardware) {
                packRow("Quality Video", "24 GB+", "Wan 2.2 4-step.", .qualityVideo)
            }
            if busy {
                ProgressView(value: progress)
                    .tint(RFTheme.gold)
            }
            if let errorText {
                Text(errorText)
                    .font(.system(size: 12))
                    .foregroundStyle(RFTheme.gold)
            }
            HStack {
                Button("I already have models") { pickExisting() }
                    .buttonStyle(GhostButtonStyle())
                Spacer()
                Button("Skip — Instant pack") { finish() }
                    .buttonStyle(GhostButtonStyle())
                    .disabled(busy)
                Button(busy ? "Working…" : "Use recommended") { useRecommended() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(busy)
            }
        }
        .padding(28)
        .frame(width: 640)
        .background(RFTheme.bg)
        .onAppear { detect() }
    }

    private func packRow(_ name: String, _ size: String, _ summary: String, _ pack: SetupPack) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.system(size: 15, weight: .semibold))
                Text(summary).font(.system(size: 12)).foregroundStyle(RFTheme.muted)
            }
            Spacer()
            Text(size).foregroundStyle(RFTheme.gold)
            if recommended == pack {
                Text("Recommended").font(.system(size: 10, weight: .bold)).foregroundStyle(RFTheme.gold)
            }
        }
        .padding(12)
        .background(RFTheme.elevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func detect() {
        hardware = Self.snapshot()
        recommended = SetupWizard.recommend(hardware)
        let label = recommended.rawValue.replacingOccurrences(of: "-", with: " ")
        detail = "Recommended: \(label). Disk \(Int(hardware.diskFreeGB)) GB free. Downloads land in Application Support — no admin."
    }

    static func snapshot() -> HardwareSnapshot {
        let ram = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        var disk: Double = 64
        if let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
           let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let free = values.volumeAvailableCapacityForImportantUsage {
            disk = Double(free) / 1_073_741_824
        }
        #if arch(arm64)
        let apple = true
        #else
        let apple = false
        #endif
        return HardwareSnapshot(nvidia: false, vramGB: 0, appleGPU: apple, ramGB: ram, diskFreeGB: disk)
    }

    private func pickExisting() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url {
            state.modelsDir = url.path
            UserDefaults.standard.set(url.path, forKey: "reelforge.modelsDir")
            finish()
        }
    }

    private func useRecommended() {
        if recommended == .instant {
            finish()
            return
        }
        busy = true
        errorText = nil
        Task {
            do {
                let manifest = try SetupWizard.loadManifest()
                let files = ModelDownload.downloadable(ModelDownload.files(for: recommended, in: manifest))
                let root = ModelDownload.modelsRoot(override: state.modelsDir.isEmpty ? nil : state.modelsDir)
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                if files.isEmpty {
                    await MainActor.run {
                        detail = "No single-file download for this pack. Point at a folder you already have, or skip Instant."
                        busy = false
                    }
                    return
                }
                for (index, file) in files.enumerated() {
                    guard let raw = file.urls.first, let url = URL(string: raw) else { continue }
                    let dest = ModelDownload.destination(for: file, modelsRoot: root)
                    await MainActor.run {
                        detail = "Downloading \(file.displayName)…"
                        progress = Double(index) / Double(max(files.count, 1))
                    }
                    try await Self.download(from: url, to: dest)
                    if !(try ModelDownload.verifyChecksum(at: dest, expected: file.sha256)) {
                        try? FileManager.default.removeItem(at: dest)
                        throw ModelDownloadError.checksumUnavailable
                    }
                }
                await MainActor.run {
                    state.modelsDir = root.path
                    UserDefaults.standard.set(root.path, forKey: "reelforge.modelsDir")
                    finish()
                }
            } catch {
                await MainActor.run {
                    busy = false
                    errorText = "That download did not finish. Hit Use recommended to retry, or Skip — Instant pack still works."
                }
            }
        }
    }

    private static func download(from url: URL, to dest: URL) async throws {
        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        let (temp, response) = try await URLSession.shared.download(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw URLError(.badServerResponse)
        }
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.moveItem(at: temp, to: dest)
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: "reelforge.setupComplete")
        state.showWizard = false
        state.refreshStatus()
    }
}

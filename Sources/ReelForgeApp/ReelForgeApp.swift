import AppKit
import SwiftUI

@main
struct ReelForgeApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .frame(minWidth: 1200, minHeight: 800)
                .background(WindowConfigurator())
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .defaultSize(width: 1440, height: 920)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Project") { state.newProject() }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandMenu("Generate") {
                Button(state.isGenerating ? "Cancel" : "Generate Reel") {
                    if state.isGenerating { state.cancel() } else { state.generate() }
                }
                .keyboardShortcut("r", modifiers: .command)
                Button("Export Again") { state.revealExport() }
                    .keyboardShortcut("e", modifiers: .command)
                    .disabled(state.exportURL == nil)
            }
        }
    }
}

private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.backgroundColor = NSColor(calibratedRed: 0.045, green: 0.045, blue: 0.055, alpha: 1)
            window.minSize = NSSize(width: 1200, height: 800)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            nsView.window?.isMovableByWindowBackground = true
        }
    }
}

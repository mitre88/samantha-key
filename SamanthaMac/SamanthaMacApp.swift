import AppKit
import SwiftUI

@main
struct SamanthaMacApp: App {
    @State private var agent = MacVoiceAgent()

    var body: some Scene {
        WindowGroup {
            MacAssistantView(agent: agent)
                .frame(minWidth: 420, idealWidth: 520, minHeight: 620, idealHeight: 720)
        }
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra("Samantha Mac", systemImage: "waveform.circle.fill") {
            Button(agent.isRunning ? "Stop listening" : "Start listening") {
                Task { await agent.toggleListening() }
            }
            Button("Show Samantha Mac") {
                NSApp.activate(ignoringOtherApps: true)
            }
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}

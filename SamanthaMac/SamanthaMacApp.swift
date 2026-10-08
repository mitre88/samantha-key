import AppKit
import SwiftUI

@main
struct SamanthaMacApp: App {
    @NSApplicationDelegateAdaptor(SamanthaMacAppDelegate.self) private var appDelegate
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

private final class SamanthaMacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        showMainWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    private func showMainWindow() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.activate(ignoringOtherApps: true)
            for window in NSApp.windows where window.canBecomeMain {
                window.setContentSize(NSSize(width: 907, height: 817))
                window.center()
                window.deminiaturize(nil)
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
}

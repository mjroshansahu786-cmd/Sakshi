import SwiftUI
import AppKit

@main
struct SakshiApp: App {
    @ObservedObject private var daemonManager = DaemonManager.shared
    @AppStorage("MascotEnabled") private var mascotEnabled = true

    // Use an AppDelegate to manage the lifecycle, global hotkeys and windows
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    private var statusText: String {
        if daemonManager.needsScreenPermission {
            return "⚠ Needs Screen Recording permission"
        }
        return daemonManager.isRunning ? "● Monitoring Active" : "○ Paused"
    }

    var body: some Scene {
        MenuBarExtra {
            Text(statusText)
                .foregroundColor(daemonManager.needsScreenPermission ? .orange : (daemonManager.isRunning ? .green : .red))

            Divider()

            Button(daemonManager.isRunning ? "Pause Recording" : "Resume Recording") {
                daemonManager.toggleDaemons()
            }

            Button("Open Quick Search (⌃Space)") {
                appDelegate.toggleQuickSearch()
            }

            Button("Show Timeline") {
                appDelegate.openTimelineWindow()
            }

            Divider()

            Button(mascotEnabled ? "Hide Companion" : "Show Companion") {
                appDelegate.setMascotEnabled(!mascotEnabled)
            }

            Button("Preferences…") {
                appDelegate.openPreferences()
            }

            Divider()

            Button("Quit SAKSHI") {
                appDelegate.quitApp()
            }
        } label: {
            if let url = Bundle.main.url(forResource: "MenuBarIconTemplate", withExtension: "png"),
               let nsImage = NSImage(contentsOf: url) {
                let _ = { nsImage.isTemplate = true }()
                Image(nsImage: nsImage)
            } else {
                Image(systemName: "eye.circle")
            }
        }
    }
}

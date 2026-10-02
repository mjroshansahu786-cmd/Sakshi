import SwiftUI
import AppKit

@main
struct SakshiApp: App {
    @ObservedObject private var daemonManager = DaemonManager.shared
    
    // Use an AppDelegate to manage the lifecycle and global hotkeys without needing a main window
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // Main Workspace Window
        WindowGroup {
            TimelineView()
                .environmentObject(daemonManager)
        }
        
        // Menu Bar Item
        MenuBarExtra {
            VStack {
                Text("SAKSHI Status: \(daemonManager.isRunning ? "● Monitoring Active" : "○ Paused")")
                    .foregroundColor(daemonManager.isRunning ? .green : .red)
                
                Divider()
                
                Button(daemonManager.isRunning ? "Pause Recording" : "Resume Recording") {
                    daemonManager.toggleDaemons()
                }
                
                Button("Open Quick Search (⌃Space)") {
                    appDelegate.showOverlay()
                }
                .keyboardShortcut(.space, modifiers: [.control])
                
                Divider()
                
                Button("Preferences...") {
                    // Open preferences
                }
                
                Button("Quit") {
                    daemonManager.stopDaemons()
                    NSApplication.shared.terminate(nil)
                }
            }
        } label: {
            if let nsImage = NSImage(contentsOfFile: "/Applications/SAKSHI.app/Contents/Resources/MenuBarIconTemplate.png") {
                let _ = { nsImage.isTemplate = true }()
                Image(nsImage: nsImage)
            } else {
                Image(systemName: "eye.circle")
            }
        }
    }
}

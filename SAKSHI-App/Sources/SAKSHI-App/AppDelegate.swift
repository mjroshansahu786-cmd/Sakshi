import Cocoa
import SwiftUI
import Carbon

class SearchPanel: NSPanel {
    override var canBecomeKey: Bool {
        return true
    }
    override var canBecomeMain: Bool {
        return true
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, @unchecked Sendable {
    var overlayPanel: SearchPanel!
    var hotKeyRef: EventHotKeyRef?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupOverlayPanel()
        registerGlobalHotKey()
        DaemonManager.shared.startDaemons()
    }
    
    @MainActor
    func setupOverlayPanel() {
        // Create a borderless, floating, non-activating panel (Spotlight style)
        overlayPanel = SearchPanel(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        overlayPanel.isMovableByWindowBackground = true
        
        overlayPanel.isFloatingPanel = true
        overlayPanel.level = .floating
        overlayPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        overlayPanel.backgroundColor = NSColor.clear
        overlayPanel.isOpaque = false
        overlayPanel.hasShadow = true
        
        let overlayView = OverlayView()
        let hostingView = NSHostingView(rootView: overlayView)
        overlayPanel.contentView = hostingView
        overlayPanel.center()
    }
    
    func registerGlobalHotKey() {
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(fourCharCode: "SAKS")
        hotKeyID.id = 1
        
        // Cmd(cmdKey) + Shift(shiftKey) + Space(49)
        var hotKeyRef: EventHotKeyRef? = nil
        let status = RegisterEventHotKey(
            UInt32(49), // Space
            UInt32(controlKey),
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        
        if status == noErr {
            self.hotKeyRef = hotKeyRef
            
            // Install Event Handler
            let eventSpec = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))]
            
            InstallEventHandler(GetEventDispatcherTarget(), { (nextHandler, theEvent, userData) -> OSStatus in
                let delegate = Unmanaged<AppDelegate>.fromOpaque(userData!).takeUnretainedValue()
                DispatchQueue.main.async {
                    delegate.toggleOverlay()
                }
                return noErr
            }, 1, eventSpec, Unmanaged.passUnretained(self).toOpaque(), nil)
        } else {
            print("Failed to register global hotkey")
        }
        
        // Fallback local monitor just in case Carbon global hotkey fails
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 49 && event.modifierFlags.contains(.control) {
                DispatchQueue.main.async {
                    self.toggleOverlay()
                }
                return nil // Consume event
            }
            return event
        }
        
        // Fallback global monitor (requires Accessibility permissions)
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 49 && event.modifierFlags.contains(.control) {
                DispatchQueue.main.async {
                    self.toggleOverlay()
                }
            }
        }
    }
    
    @MainActor
    @objc func toggleOverlay() {
        if overlayPanel.isVisible {
            overlayPanel.orderOut(nil)
        } else {
            showOverlay()
        }
    }
    
    @MainActor
    func showOverlay() {
        // Re-create the content view so it fetches fresh data on every open
        let overlayView = OverlayView()
        let hostingView = NSHostingView(rootView: overlayView)
        overlayPanel.contentView = hostingView
        overlayPanel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// Helper to create OSType from 4 char string
extension OSType {
    init(fourCharCode string: String) {
        var res: UInt32 = 0
        for unicodeScalar in string.unicodeScalars {
            res = (res << 8) + (unicodeScalar.value & 255)
        }
        self = res
    }
}

import Cocoa
import SwiftUI
import Carbon
import ApplicationServices
import Darwin

class SearchPanel: NSPanel {
    override var canBecomeKey: Bool {
        return true
    }
    override var canBecomeMain: Bool {
        return true
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, MascotActions, @unchecked Sendable {
    var overlayPanel: SearchPanel!
    var hotKeyRef: EventHotKeyRef?
    private var timelineWindow: NSWindow?
    private var preferencesWindow: NSWindow?
    private var mascotController: MascotController?
    private var lastToggleAt = Date.distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Line-buffer stdout so logs written via the LaunchAgent redirect
        // (~/.mnemos/logs/app.log) are flushed immediately.
        setvbuf(stdout, nil, _IOLBF, 8192)

        setupOverlayPanel()
        registerGlobalHotKey()

        // Make sure the Accessibility prompt appears if window titles aren't readable yet
        ensureAccessibilityPermission()

        DaemonManager.shared.startDaemons()

        // Companion mascot (on by default)
        if UserDefaults.standard.object(forKey: "MascotEnabled") == nil {
            UserDefaults.standard.set(true, forKey: "MascotEnabled")
        }
        mascotController = MascotController(actions: self)
        if UserDefaults.standard.bool(forKey: "MascotEnabled") {
            mascotController?.show()
        }
    }

    private func ensureAccessibilityPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
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

        let overlayView = OverlayView(onRequestClose: { [weak self] in
            self?.hideOverlay()
        })
        let hostingView = NSHostingView(rootView: overlayView)
        overlayPanel.contentView = hostingView
        overlayPanel.center()
    }

    func registerGlobalHotKey() {
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(fourCharCode: "SAKS")
        hotKeyID.id = 1

        // Ctrl(controlKey) + Space(49)
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
                    delegate.toggleQuickSearch()
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
                    self.toggleQuickSearch()
                }
                return nil // Consume event
            }
            return event
        }

        // Fallback global monitor (requires Accessibility permissions)
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 49 && event.modifierFlags.contains(.control) {
                DispatchQueue.main.async {
                    self.toggleQuickSearch()
                }
            }
        }
    }

    /// Guard against Carbon hotkey + event monitors firing twice for one press.
    @MainActor
    @objc func toggleQuickSearch() {
        let now = Date()
        guard now.timeIntervalSince(lastToggleAt) > 0.35 else { return }
        lastToggleAt = now
        toggleOverlay()
    }

    @MainActor
    @objc func toggleOverlay() {
        if overlayPanel.isVisible {
            hideOverlay()
        } else {
            showOverlay()
        }
    }

    @MainActor
    @objc func hideOverlay() {
        overlayPanel.orderOut(nil)
    }

    @MainActor
    func showOverlay() {
        // Re-create the content view so it fetches fresh data on every open
        let overlayView = OverlayView(onRequestClose: { [weak self] in
            self?.hideOverlay()
        })
        let hostingView = NSHostingView(rootView: overlayView)
        overlayPanel.contentView = hostingView
        overlayPanel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Windows

    @MainActor
    @objc func openTimelineWindow() {
        if timelineWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1020, height: 680),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "SAKSHI Timeline"
            window.minSize = NSSize(width: 900, height: 600)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(
                rootView: TimelineView().environmentObject(DaemonManager.shared)
            )
            window.center()
            timelineWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        timelineWindow?.makeKeyAndOrderFront(nil)
    }

    @MainActor
    @objc func openPreferences() {
        if preferencesWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 430, height: 400),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "SAKSHI Preferences"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(
                rootView: PreferencesView(
                    onMascotEnabledChanged: { [weak self] enabled in
                        self?.setMascotEnabled(enabled)
                    },
                    onMascotPositionReset: { [weak self] in
                        self?.resetMascotPosition()
                    }
                )
            )
            window.center()
            preferencesWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        preferencesWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Mascot

    @MainActor
    func toggleRecording() {
        DaemonManager.shared.toggleDaemons()
    }

    @MainActor
    func hideMascot() {
        setMascotEnabled(false)
    }

    @MainActor
    func setMascotEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "MascotEnabled")
        if enabled {
            mascotController?.show()
        } else {
            mascotController?.hide()
        }
    }

    @MainActor
    func resetMascotPosition() {
        UserDefaults.standard.removeObject(forKey: "MascotOrbX")
        UserDefaults.standard.removeObject(forKey: "MascotY")
        UserDefaults.standard.removeObject(forKey: "MascotDock")
        mascotController?.hide()
        mascotController = MascotController(actions: self)
        if UserDefaults.standard.bool(forKey: "MascotEnabled") {
            mascotController?.show()
        }
    }

    @objc func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func quitApp() {
        DaemonManager.shared.stopDaemons()
        NSApp.terminate(nil)
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

import AppKit
import SwiftUI

/// Actions the mascot can invoke. Implemented by AppDelegate so the mascot,
/// the menu-bar menu and the context menu all share one set of behaviors.
@MainActor @objc protocol MascotActions {
    @objc func openTimelineWindow()
    @objc func toggleQuickSearch()
    @objc func toggleRecording()
    @objc func openScreenRecordingSettings()
    @objc func openPreferences()
    @objc func hideMascot()
    @objc func quitApp()
}

/// Floating always-on-top panel hosting the companion orb.
final class MascotPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// NSView that hosts the SwiftUI orb, owns the mouse handling (drag, click,
/// right-click menu) and passes clicks through everywhere else.
final class MascotRootView: NSView {
    weak var controller: MascotController?
    weak var actions: MascotActions?
    let vm: MascotViewModel
    private var hostingView: NSHostingView<MascotView>!
    private var trackingArea: NSTrackingArea?

    init(vm: MascotViewModel) {
        self.vm = vm
        super.init(frame: NSRect(origin: .zero, size: MascotLayout.baseSize))
        hostingView = NSHostingView(rootView: MascotView(vm: vm))
        hostingView.autoresizingMask = [.width, .height]
        addSubview(hostingView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        hostingView.frame = bounds
    }

    /// Region occupied by the orb (pinned to the trailing edge of the panel).
    var orbRect: NSRect {
        NSRect(x: bounds.width - MascotLayout.padding - MascotLayout.orbSize,
               y: MascotLayout.padding,
               width: MascotLayout.orbSize,
               height: MascotLayout.orbSize)
    }

    private func isOverOrb(_ pointInWindow: NSPoint) -> Bool {
        let local = convert(pointInWindow, from: nil)
        return orbRect.insetBy(dx: -6, dy: -6).contains(local)
    }

    /// Only the orb is interactive; the rest of the (invisible) panel lets
    /// clicks fall through to whatever is underneath.
    override func hitTest(_ point: NSPoint) -> NSView? {
        isOverOrb(point) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = trackingArea { removeTrackingArea(area) }
        let area = NSTrackingArea(
            rect: orbRect,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func resetCursorRects() {
        addCursorRect(orbRect, cursor: .pointingHand)
    }

    // MARK: Mouse handling

    private var dragStartWindowPoint: NSPoint?
    private var dragStartOrigin: NSPoint?
    private var dragMovedEnough = false

    override func mouseDown(with event: NSEvent) {
        guard isOverOrb(event.locationInWindow) else { return }
        dragStartWindowPoint = event.locationInWindow
        dragStartOrigin = window?.frame.origin
        dragMovedEnough = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStartWindowPoint,
              let origin = dragStartOrigin,
              let win = window else { return }
        let dx = event.locationInWindow.x - start.x
        let dy = event.locationInWindow.y - start.y
        if !dragMovedEnough, abs(dx) > 3 || abs(dy) > 3 {
            dragMovedEnough = true
            vm.dragging = true
            controller?.beginDragging()
        }
        guard dragMovedEnough else { return }
        var newOrigin = NSPoint(x: origin.x + dx, y: origin.y + dy)
        let allScreens = NSScreen.screens
        let minY = allScreens.map { $0.frame.minY }.min() ?? -4000
        let maxY = allScreens.map { $0.frame.maxY }.max() ?? 4000
        newOrigin.y = min(max(newOrigin.y, minY + 4), maxY - win.frame.height - 4)
        win.setFrameOrigin(newOrigin)
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragStartWindowPoint = nil
            dragStartOrigin = nil
        }
        if dragMovedEnough {
            dragMovedEnough = false
            vm.dragging = false
            controller?.endDragging()
        } else {
            controller?.noteInteraction()
            actions?.toggleQuickSearch()
        }
    }

    override func otherMouseDown(with event: NSEvent) {
        guard isOverOrb(event.locationInWindow) else { return }
        showContextMenu(at: NSEvent.mouseLocation)
    }

    override func mouseEntered(with event: NSEvent) {
        vm.hover = true
        controller?.wake()
    }

    override func mouseExited(with event: NSEvent) {
        vm.hover = false
        controller?.noteInteraction()
    }

    // MARK: Context menu

    private func showContextMenu(at screenPoint: NSPoint) {
        let menu = NSMenu()
        let watching = vm.status == .watching

        menu.addItem(withTitle: "Open Timeline", action: #selector(MascotActions.openTimelineWindow), target: actions)
        menu.addItem(withTitle: "Quick Search", action: #selector(MascotActions.toggleQuickSearch), target: actions)
        menu.addItem(.separator())

        let recordTitle = watching ? "Pause Recording" : "Resume Recording"
        menu.addItem(withTitle: recordTitle, action: #selector(MascotActions.toggleRecording), target: actions)

        if vm.status == .needsPermission {
            menu.addItem(withTitle: "Open Screen Recording Settings…", action: #selector(MascotActions.openScreenRecordingSettings), target: actions)
        }

        menu.addItem(.separator())
        menu.addItem(withTitle: "Preferences…", action: #selector(MascotActions.openPreferences), target: actions)
        menu.addItem(withTitle: "Hide Companion", action: #selector(MascotActions.hideMascot), target: actions)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit SAKSHI", action: #selector(MascotActions.quitApp), target: actions)

        menu.popUp(positioning: nil, at: convert(screenPoint, from: nil), in: self)
    }
}

private extension NSMenu {
    func addItem(withTitle title: String, action: Selector, target: AnyObject?) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target
        addItem(item)
    }
}

// MARK: - Controller

@MainActor
final class MascotController: NSObject {
    static let idlePeekDelay: TimeInterval = 6

    let vm = MascotViewModel()
    private var panel: MascotPanel!
    private weak var actions: MascotActions?
    private var tickTask: Task<Void, Never>?
    private var baseFrame: NSRect = .zero
    private var dockedRight = true
    private var isPeeked = false
    private var isDragging = false
    private var lastInteraction = Date()

    init(actions: MascotActions) {
        super.init()
        self.actions = actions
        panel = MascotPanel(
            contentRect: NSRect(origin: .zero, size: MascotLayout.baseSize),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.worksWhenModal = true

        let root = MascotRootView(vm: vm)
        root.controller = self
        root.actions = actions
        panel.contentView = root

        baseFrame = loadFrame()
        panel.setFrame(baseFrame, display: false)
    }

    // MARK: Visibility

    func show() {
        if tickTask == nil {
            tickTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    if !Task.isCancelled { self?.tick() }
                }
            }
        }
        if !(panel?.isVisible ?? false) {
            // Slide in from beyond the screen edge for a little spawn flourish
            let offscreen = baseFrame.offsetBy(dx: (dockedRight ? 1 : -1) * (baseFrame.width + 80), dy: 0)
            panel.setFrame(offscreen, display: false)
            panel.orderFrontRegardless()
            animateFrame(to: baseFrame, duration: 0.45)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + MascotController.idlePeekDelay) { [weak self] in
            self?.noteInteraction()
        }
    }

    func hide() {
        tickTask?.cancel()
        tickTask = nil
        panel?.orderOut(nil)
    }

    var isShown: Bool { panel?.isVisible ?? false }

    // MARK: Frame management
    // All positions are expressed as the orb's anchor edge:
    // right dock -> orb's right-edge X; left dock -> orb's left-edge X.

    private func frame(orbTarget: CGFloat, dockedRight side: Bool, y: CGFloat) -> NSRect {
        let size = MascotLayout.baseSize
        let x = side ? orbTarget - (size.width - MascotLayout.padding)
                     : orbTarget - MascotLayout.padding
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func loadFrame() -> NSRect {
        let defaults = UserDefaults.standard
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        dockedRight = defaults.string(forKey: "MascotDock") != "left"

        if defaults.object(forKey: "MascotOrbX") != nil,
           defaults.object(forKey: "MascotY") != nil {
            let orbTarget = defaults.double(forKey: "MascotOrbX")
            let y = clampY(defaults.double(forKey: "MascotY"), in: screen)
            return frame(orbTarget: orbTarget, dockedRight: dockedRight, y: y)
        }

        // Default: right edge, upper third — like a docked assistant tab.
        let orbTarget = dockedRight
            ? screen.maxX - MascotLayout.edgeMargin
            : screen.minX + MascotLayout.edgeMargin
        let orbCenterY = screen.maxY - screen.height * 0.32
        let y = clampY(orbCenterY - MascotLayout.padding - MascotLayout.orbSize / 2, in: screen)
        return frame(orbTarget: orbTarget, dockedRight: dockedRight, y: y)
    }

    private func clampY(_ y: CGFloat, in screen: NSRect) -> CGFloat {
        min(max(y, screen.minY + 8), screen.maxY - MascotLayout.baseSize.height - 8)
    }

    private func animateFrame(to target: NSRect, duration: TimeInterval = 0.32) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            panel.setFrame(target, display: true)
        }, completionHandler: nil)
    }

    // MARK: Interaction hooks from the root view

    func beginDragging() {
        isDragging = true
        isPeeked = false
    }

    func endDragging() {
        isDragging = false
        guard let screen = nearestScreen(for: panel.frame)?.visibleFrame else { return }
        dockedRight = panel.frame.midX > screen.midX
        let orbTarget = dockedRight
            ? screen.maxX - MascotLayout.edgeMargin
            : screen.minX + MascotLayout.edgeMargin
        let y = clampY(panel.frame.minY, in: screen)
        baseFrame = frame(orbTarget: orbTarget, dockedRight: dockedRight, y: y)
        isPeeked = false
        animateFrame(to: baseFrame)

        let defaults = UserDefaults.standard
        defaults.set(Double(orbTarget), forKey: "MascotOrbX")
        defaults.set(Double(baseFrame.minY), forKey: "MascotY")
        defaults.set(dockedRight ? "right" : "left", forKey: "MascotDock")
    }

    private func nearestScreen(for frame: NSRect) -> NSScreen? {
        NSScreen.screens.first { $0.frame.intersects(frame) } ?? NSScreen.main
    }

    func wake() {
        noteInteraction()
        guard !isDragging, isPeeked else { return }
        isPeeked = false
        animateFrame(to: baseFrame, duration: 0.25)
    }

    /// Peek after a period without interaction: tuck the orb halfway into the
    /// screen edge so it never blocks content.
    private func peekIfIdle() {
        guard !isDragging, !isPeeked, !vm.hover, !vm.dragging else { return }
        let screen = NSScreen.main?.visibleFrame ?? baseFrame
        let peekOut = MascotLayout.orbSize - MascotLayout.sliver
        let orbTarget = dockedRight ? screen.maxX + peekOut : screen.minX - peekOut
        isPeeked = true
        animateFrame(to: frame(orbTarget: orbTarget, dockedRight: dockedRight, y: baseFrame.minY), duration: 0.45)
    }

    func noteInteraction() {
        lastInteraction = Date()
    }

    /// Called every second: reconciles status from DaemonManager and peeks
    /// after a period without interaction.
    func tick() {
        let daemon = DaemonManager.shared
        vm.lastCaptureAt = daemon.lastCaptureAt
        if daemon.needsScreenPermission {
            vm.status = .needsPermission
        } else {
            vm.status = daemon.isRunning ? .watching : .paused
        }
        if Date().timeIntervalSince(lastInteraction) > MascotController.idlePeekDelay {
            peekIfIdle()
        }
    }
}

import SwiftUI

// Shared geometry between the AppKit drag/hit-test layer and the SwiftUI layout.
enum MascotLayout {
    static let orbSize: CGFloat = 56
    static let padding: CGFloat = 10
    static let gap: CGFloat = 6
    static let bubbleWidth: CGFloat = 168
    static let sliver: CGFloat = 24 // visible width while peeked
    static let edgeMargin: CGFloat = 10

    /// Panel is always the expanded width; the bubble region is click-through
    /// when hidden, so no window resizing is ever needed.
    static var baseSize: CGSize {
        CGSize(width: padding * 2 + orbSize + gap + bubbleWidth,
               height: padding * 2 + orbSize)
    }
}

enum MascotStatus {
    case watching
    case paused
    case needsPermission

    var accent: Color {
        switch self {
        case .watching: Color(red: 0.20, green: 0.80, blue: 0.47)
        case .paused: Color(white: 0.68)
        case .needsPermission: Color(red: 0.95, green: 0.32, blue: 0.28)
        }
    }

    var title: String {
        switch self {
        case .watching: "SAKSHI · Watching"
        case .paused: "SAKSHI · Paused"
        case .needsPermission: "Permission needed"
        }
    }
}

@MainActor
final class MascotViewModel: ObservableObject {
    @Published var hover = false
    @Published var dragging = false
    @Published var status: MascotStatus = .paused
    @Published var lastCaptureAt: Date?
}

// MARK: - Root composition

struct MascotView: View {
    @ObservedObject var vm: MascotViewModel

    private var bubbleVisible: Bool { vm.hover || vm.dragging }

    var body: some View {
        HStack(spacing: MascotLayout.gap) {
            if bubbleVisible {
                MascotStatusBubble(vm: vm)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            MascotOrb(vm: vm)
        }
        .padding(MascotLayout.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .animation(.easeOut(duration: 0.22), value: bubbleVisible)
    }
}

// MARK: - The orb

struct MascotOrb: View {
    @ObservedObject var vm: MascotViewModel

    @State private var pingScale: CGFloat = 1.0
    @State private var pingOpacity: Double = 0
    @State private var capturing = false
    @State private var blinkClosed = false

    private var presentation: MascotStatus { vm.status }

    var body: some View {
        ZStack {
            // Ambient glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [presentation.accent.opacity(0.5), .clear],
                        center: .center,
                        startRadius: MascotLayout.orbSize * 0.35,
                        endRadius: MascotLayout.orbSize * 0.85
                    )
                )
                .frame(width: MascotLayout.orbSize + 16, height: MascotLayout.orbSize + 16)
                .blur(radius: 6)
                .opacity(vm.dragging ? 0.95 : (vm.hover ? 0.7 : 0.4))

            // Heartbeat halo while watching
            if presentation == .watching && !vm.dragging {
                HaloRing(color: presentation.accent)
            }

            // Ping ring emitted on every successful capture
            Circle()
                .stroke(presentation.accent.opacity(pingOpacity), lineWidth: 2)
                .frame(width: MascotLayout.orbSize, height: MascotLayout.orbSize)
                .scaleEffect(pingScale)

            // Rotating arc while a frame is being processed
            if capturing {
                Circle()
                    .trim(from: 0, to: 0.2)
                    .stroke(presentation.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: MascotLayout.orbSize + 8, height: MascotLayout.orbSize + 8)
                    .rotationEffect(.degrees(captureRotation))
                    .onAppear {
                        withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                            captureRotation = 360
                        }
                    }
            }

            // Core
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(red: 1.0, green: 0.80, blue: 0.55),
                                 Color(red: 0.98, green: 0.55, blue: 0.25),
                                 Color(red: 0.85, green: 0.33, blue: 0.12)],
                        center: UnitPoint(x: 0.35, y: 0.3),
                        startRadius: 2,
                        endRadius: MascotLayout.orbSize * 0.7
                    )
                )
                .frame(width: MascotLayout.orbSize, height: MascotLayout.orbSize)

            Circle()
                .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                .frame(width: MascotLayout.orbSize, height: MascotLayout.orbSize)

            // The eye
            Image(systemName: presentation == .paused ? "eye.slash" : "eye")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(.white)
                .scaleEffect(x: 1, y: blinkClosed ? 0.12 : 1, anchor: .center)
        }
        .frame(width: MascotLayout.orbSize, height: MascotLayout.orbSize)
        .scaleEffect(vm.hover || vm.dragging ? 1.06 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: vm.hover || vm.dragging)
        .onChange(of: vm.lastCaptureAt) { _, _ in
            triggerCapturePulse()
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            maybeBlink()
        }
    }

    @State private var captureRotation: Double = 0

    private func triggerCapturePulse() {
        pingScale = 1.0
        pingOpacity = 0.9
        withAnimation(.easeOut(duration: 0.8)) {
            pingScale = 1.55
            pingOpacity = 0
        }
        capturing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            capturing = false
        }
    }

    private func maybeBlink() {
        guard presentation == .watching, !blinkClosed, Double.random(in: 0...1) < 0.16 else { return }
        withAnimation(.easeInOut(duration: 0.09)) { blinkClosed = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            withAnimation(.easeInOut(duration: 0.09)) { blinkClosed = false }
        }
    }
}

struct HaloRing: View {
    let color: Color
    @State private var pulse = false

    var body: some View {
        Circle()
            .stroke(color.opacity(0.55), lineWidth: 1.5)
            .frame(width: MascotLayout.orbSize + 10, height: MascotLayout.orbSize + 10)
            .scaleEffect(pulse ? 1.1 : 1.0)
            .opacity(pulse ? 0.3 : 0.85)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

// MARK: - Status bubble

struct MascotStatusBubble: View {
    @ObservedObject var vm: MascotViewModel
    @State private var now = Date()

    private var detail: String {
        switch vm.status {
        case .paused:
            return "Recording is turned off"
        case .needsPermission:
            return "Enable Screen Recording in System Settings"
        case .watching:
            guard let last = vm.lastCaptureAt else { return "Building your memory…" }
            let secs = max(0, now.timeIntervalSince(last))
            if secs < 5 { return "Last frame just now" }
            if secs < 90 { return "Last frame \(Int(secs))s ago" }
            return "Last frame \(Int(secs / 60))m ago"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Circle()
                    .fill(vm.status.accent)
                    .frame(width: 7, height: 7)
                Text(vm.status.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(vm.dragging ? "Release to snap to edge" : "Click to search · Drag to move")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
        )
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.08)))
        .frame(width: MascotLayout.bubbleWidth, alignment: .leading)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            now = Date()
        }
    }
}

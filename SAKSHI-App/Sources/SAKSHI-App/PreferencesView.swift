import SwiftUI

struct PreferencesView: View {
    @AppStorage("MascotEnabled") private var mascotEnabled = true
    @AppStorage("CaptureInterval") private var captureInterval: Double = 60

    var onMascotEnabledChanged: ((Bool) -> Void)?
    var onMascotPositionReset: (() -> Void)?

    @State private var backendStatus: BackendStatus = .checking
    @State private var statusTask: Task<Void, Never>?

    struct BackendStatusText: Equatable {
        var line1: String
        var line2: String
        var ok: Bool
    }

    enum BackendStatus: Equatable {
        case checking, ok(BackendStatusText), failed(String)
    }

    var body: some View {
        Form {
            Section("Companion") {
                Toggle("Show SAKSHI companion on screen edge", isOn: Binding(
                    get: { mascotEnabled },
                    set: { newValue in
                        mascotEnabled = newValue
                        onMascotEnabledChanged?(newValue)
                    }
                ))
                Button("Reset Companion Position") {
                    onMascotPositionReset?()
                }
            }

            Section("Capture") {
                Picker("Capture screen every", selection: Binding(
                    get: { Int(captureInterval) },
                    set: { captureInterval = Double($0) }
                )) {
                    Text("30 sec").tag(30)
                    Text("1 min").tag(60)
                    Text("90 sec").tag(90)
                    Text("2 min").tag(120)
                }
                .pickerStyle(.segmented)
                Text("Longer intervals use less CPU, battery and disk. Applies on the next capture cycle.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Backend") {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        switch backendStatus {
                        case .checking:
                            HStack(spacing: 6) {
                                ProgressView().scaleEffect(0.6)
                                Text("Checking backend…").font(.callout)
                            }
                        case .ok(let text):
                            Label(text.line1, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.callout)
                            Text(text.line2).font(.caption).foregroundStyle(.secondary)
                        case .failed(let reason):
                            Label("Backend unreachable", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.callout)
                            Text(reason).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Refresh") { checkBackend() }
                        .disabled(backendStatus == .checking)
                }

                if !DaemonManager.shared.backendBasePath.isEmpty {
                    Text("Backend: \(DaemonManager.shared.backendBasePath)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 430, height: 400)
        .onAppear { checkBackend() }
        .onDisappear { statusTask?.cancel() }
    }

    private func checkBackend() {
        statusTask?.cancel()
        backendStatus = .checking
        statusTask = Task {
            var request = URLRequest(url: URL(string: "http://127.0.0.1:8765/status")!)
            request.timeoutInterval = 3
            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw URLError(.cannotDecodeContentData)
                }
                let ollama = obj["ollama"] as? Bool ?? false
                let captured = obj["raw_events"] as? Int ?? 0
                let summaries = obj["summaries"] as? Int ?? 0
                let text = BackendStatusText(
                    line1: "API running · Ollama \(ollama ? "ready" : "not detected")",
                    line2: "\(captured) events captured · \(summaries) summaries indexed",
                    ok: true
                )
                if Task.isCancelled { return }
                backendStatus = .ok(text)
            } catch {
                if Task.isCancelled { return }
                backendStatus = .failed("Start the app's recording from the menu bar, or launch mnemos-backend/api.py manually. (\(error.localizedDescription))")
            }
        }
    }
}

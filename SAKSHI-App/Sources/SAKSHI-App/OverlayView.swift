import SwiftUI

struct ContextResult: Codable, Identifiable {
    let id: String
    let start_time: String
    let end_time: String
    let summary_crux: String
    let score: Double
}

struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .active
        view.blendingMode = .behindWindow
        view.material = .hudWindow
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct OverlayView: View {
    var onRequestClose: (() -> Void)?

    @State private var query = ""
    @State private var results: [ContextResult] = []
    @State private var isSearching = false
    @State private var errorMessage: String? = nil
    @State private var searchTask: Task<Void, Never>?
    @State private var hasSearchedOnce = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                    .font(.title2)

                TextField("Search memories, apps, audio...", text: $query)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 24, weight: .light))
                    .autocorrectionDisabled()
                    .onChange(of: query) { _, _ in
                        scheduleSearch()
                    }
                    .onSubmit {
                        runSearch()
                    }

                if isSearching {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .padding(20)

            Divider()

            if let err = errorMessage {
                Text(err).foregroundColor(.red).padding()
            }

            if !results.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(results) { result in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(formatTimeRanges(result.start_time, result.end_time))
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .textSelection(.enabled)

                                Text(cleanSummary(result.summary_crux))
                                    .font(.body)
                                    .lineLimit(4)
                                    .textSelection(.enabled)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                            .cornerRadius(12)
                        }
                    }
                    .padding()
                }
            } else if !isSearching {
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 34))
                        .foregroundColor(.gray.opacity(0.6))
                    Text(emptyStateText)
                        .foregroundColor(.gray)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 60)
            }
            Spacer(minLength: 0)

            Text("↩ to search · Esc to close")
                .font(.caption2)
                .foregroundColor(.gray.opacity(0.7))
                .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(VisualEffectView().ignoresSafeArea())
        .cornerRadius(20)
        .onExitCommand {
            onRequestClose?()
        }
        .onAppear {
            runSearch()
        }
    }

    private var emptyStateText: String {
        if let err = errorMessage {
            return err
        }
        if !hasSearchedOnce {
            return "SAKSHI hasn't captured anything yet.\nIt will start building your timeline automatically."
        }
        return "No memories matched \"\(query)\" yet."
    }

    /// Debounced search: cancels any in-flight request and waits for typing to settle.
    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return }
            runSearch()
        }
    }

    private func runSearch() {
        searchTask?.cancel()
        searchTask = Task {
            await performSearch()
        }
    }

    private func performSearch(attempt: Int = 0) async {
        isSearching = true

        guard let url = URL(string: "http://localhost:8765/query") else {
            isSearching = false
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 8

        let body: [String: Any] = ["query": query, "limit": 15]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if Task.isCancelled { return }
            let decoded = try JSONDecoder().decode([ContextResult].self, from: data)
            results = decoded
            errorMessage = nil
            hasSearchedOnce = true
            isSearching = false
        } catch {
            if Task.isCancelled { return }
            // Retry a connection failure a few times (backend may still be booting),
            // but never retry forever like the old implementation did.
            if (error as? URLError)?.code == .cannotConnectToHost || (error as? URLError)?.code == .timedOut {
                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    guard !Task.isCancelled else { return }
                    await performSearch(attempt: attempt + 1)
                    return
                }
                errorMessage = "Can't reach the SAKSHI backend on :8765"
            } else if let decodeError = error as? DecodingError {
                errorMessage = "Decode error: \(decodeError.localizedDescription)"
            } else {
                errorMessage = "Search failed: \(error.localizedDescription)"
            }
            isSearching = false
        }
    }

    func formatTimeRanges(_ start: String, _ end: String) -> String {
        let formatter = ISO8601DateFormatter()
        let displayFormatter = DateFormatter()
        displayFormatter.timeStyle = .short

        guard let sDate = formatter.date(from: start),
              let eDate = formatter.date(from: end) else {
            return "\(start) - \(end)"
        }
        return "\(displayFormatter.string(from: sDate)) to \(displayFormatter.string(from: eDate))"
    }

    func cleanSummary(_ text: String) -> String {
        var cleaned = text

        // Find the start of the first bullet point
        if let bulletRange = cleaned.range(of: "•") {
            cleaned = String(cleaned[bulletRange.lowerBound...])
        } else if let bulletRange = cleaned.range(of: "-") {
            cleaned = String(cleaned[bulletRange.lowerBound...])
        }

        // Remove common LLM boilerplate prefixes
        let prefixesToRemove = [
            "• **Core Focus:** The user appears to be ",
            "• **Core Focus:** The user is ",
            "• **Core Focus:** ",
            "- **Core Focus:** The user appears to be ",
            "- **Core Focus:** The user is ",
            "- **Core Focus:** "
        ]

        for prefix in prefixesToRemove {
            if cleaned.hasPrefix(prefix) {
                // Return just the capitalized action!
                let action = String(cleaned.dropFirst(prefix.count))
                // Capitalize the first letter
                if let first = action.first {
                    return first.uppercased() + action.dropFirst()
                }
                return action
            }
        }

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

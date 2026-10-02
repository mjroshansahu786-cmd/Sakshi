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
    @State private var query = ""
    @State private var results: [ContextResult] = []
    @State private var isSearching = false
    @State private var errorMessage: String? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                    .font(.title2)
                
                TextField("Search memories, apps, audio...", text: $query)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 24, weight: .light))
                    .onChange(of: query) { oldValue, newValue in
                        performSearch()
                    }
                    .onSubmit {
                        performSearch()
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
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(VisualEffectView().ignoresSafeArea())
        .cornerRadius(20)
        .onAppear {
            performSearch()
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

    func performSearch() {
        isSearching = true
        
        guard let url = URL(string: "http://localhost:8765/query") else { 
            return 
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 5
        
        let body: [String: Any] = ["query": query, "limit": 15]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isSearching = false
                if let error = error {
                    self.errorMessage = "Connecting to backend..."
                    // Retry after 3 seconds if backend isn't up yet
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        self.performSearch()
                    }
                    return
                }
                if let data = data {
                    do {
                        self.results = try JSONDecoder().decode([ContextResult].self, from: data)
                        self.errorMessage = nil
                    } catch {
                        self.errorMessage = "Decode error: \(error.localizedDescription)"
                    }
                }
            }
        }.resume()
    }
    
    func formatDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: iso) {
            let out = DateFormatter()
            out.timeStyle = .short
            out.dateStyle = .medium
            return out.string(from: date)
        }
        return iso
    }
}


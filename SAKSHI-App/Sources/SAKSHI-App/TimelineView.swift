import SwiftUI

struct TimelineView: View {
    @EnvironmentObject var daemonManager: DaemonManager
    
    var body: some View {
        NavigationView {
            // Sidebar Navigation
            List {
                Section(header: Text("Views")) {
                    NavigationLink(destination: FeedView()) {
                        Label("Timeline", systemImage: "clock")
                    }
                    NavigationLink(destination: Text("Diagnostics (Coming Soon)")) {
                        Label("Diagnostics", systemImage: "waveform.path.ecg")
                    }
                }
                
                Section(header: Text("Daemon Controls")) {
                    Button(action: {
                        daemonManager.toggleDaemons()
                    }) {
                        HStack {
                            Circle()
                                .fill(daemonManager.isRunning ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                            Text(daemonManager.isRunning ? "Recording Active" : "Paused")
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .listStyle(SidebarListStyle())
            .frame(minWidth: 200)
            
            // Default Detail View
            FeedView()
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}

struct FeedView: View {
    @State private var recentLogs: [ContextResult] = []
    
    var body: some View {
        VStack {
            HStack {
                Text("Recent Activity Feed")
                    .font(.title)
                    .fontWeight(.bold)
                Spacer()
                Button("Refresh") {
                    fetchRecent()
                }
            }
            .padding()
            
            if recentLogs.isEmpty {
                VStack {
                    Spacer()
                    ProgressView("Fetching memory...")
                        .onAppear(perform: fetchRecent)
                    Spacer()
                }
            } else {
                ScrollView {
                    VStack(spacing: 24) {
                        ForEach(recentLogs) { log in
                            TimelineCard(log: log)
                        }
                    }
                    .padding()
                }
            }
        }
        .background(Color(NSColor.underPageBackgroundColor))
    }
    
    func fetchRecent() {
        guard let url = URL(string: "http://localhost:8765/query") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Query an empty string to get the most recent activity
        let body: [String: Any] = ["query": "", "limit": 20]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, _, _ in
            if let data = data {
                if let decoded = try? JSONDecoder().decode([ContextResult].self, from: data) {
                    DispatchQueue.main.async {
                        self.recentLogs = decoded
                    }
                }
            }
        }.resume()
    }
}

struct TimelineCard: View {
    let log: ContextResult
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Timeline line and dot
            VStack {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 12, height: 12)
                    .padding(.top, 4)
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 2)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text(formatDate(log.start_time))
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                
                Text(log.summary_crux)
                    .font(.body)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                
                HStack {
                    Button("Copy Summary") {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(log.summary_crux, forType: .string)
                    }
                    .buttonStyle(LinkButtonStyle())
                }
                .padding(.top, 8)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
            
            Spacer()
        }
    }
    
    func formatDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: iso) {
            let out = DateFormatter()
            out.timeStyle = .short
            out.dateStyle = .medium
            return out.string(from: date)
        }
        return iso
    }
}

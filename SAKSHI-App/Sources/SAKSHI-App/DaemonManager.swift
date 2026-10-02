import Foundation

@MainActor
class DaemonManager: ObservableObject {
    static let shared = DaemonManager()
    
    @Published var isRunning = false
    
    private var processes: [Process] = []
    
    func toggleDaemons() {
        if isRunning {
            stopDaemons()
        } else {
            startDaemons()
        }
    }
    
    func startDaemons() {
        guard !isRunning else { return }
        
        // Kill any zombie processes from previous runs
        killExistingProcesses()
        
        let basePath = "/Users/roshan/Antigravity/SAKSHI/Mnemos"
        
        // 1. Swift Daemon
        startProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/swift"),
            arguments: ["run", "mnemos-daemon"],
            currentDirectory: URL(fileURLWithPath: "\(basePath)/mnemos-daemon"),
            logFileName: "daemon.log"
        )
        
        // 2. Python Ingester
        startProcess(
            executableURL: URL(fileURLWithPath: "\(basePath)/mnemos-backend/.venv/bin/python3"),
            arguments: ["ingester.py"],
            currentDirectory: URL(fileURLWithPath: "\(basePath)/mnemos-backend"),
            logFileName: "ingester.log"
        )
        
        // 3. Python Summarizer
        startProcess(
            executableURL: URL(fileURLWithPath: "\(basePath)/mnemos-backend/.venv/bin/python3"),
            arguments: ["summarizer.py"],
            currentDirectory: URL(fileURLWithPath: "\(basePath)/mnemos-backend"),
            logFileName: "summarizer.log"
        )
        
        // 4. FastAPI Server
        startProcess(
            executableURL: URL(fileURLWithPath: "\(basePath)/mnemos-backend/.venv/bin/python3"),
            arguments: ["api.py"],
            currentDirectory: URL(fileURLWithPath: "\(basePath)/mnemos-backend"),
            logFileName: "api.log"
        )
        
        isRunning = true
    }
    
    /// Kill leftover processes from a previous app run to prevent port conflicts
    private func killExistingProcesses() {
        let killCommands = [
            "pkill -f 'ingester.py'",
            "pkill -f 'summarizer.py'",
            "pkill -f 'api.py'",
            "pkill -f 'mnemos-daemon'"
        ]
        for cmd in killCommands {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", cmd]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try? process.run()
            process.waitUntilExit()
        }
        // Give OS time to release ports
        Thread.sleep(forTimeInterval: 1.0)
    }
    
    private func startProcess(executableURL: URL, arguments: [String], currentDirectory: URL? = nil, logFileName: String) {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        if let currentDirectory = currentDirectory {
            process.currentDirectoryURL = currentDirectory
        }
        
        // Setup environment for unbuffered output
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        process.environment = env
        
        let logsDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".mnemos/logs")
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        let logFileUrl = logsDir.appendingPathComponent(logFileName)
        
        FileManager.default.createFile(atPath: logFileUrl.path, contents: nil, attributes: nil)
        
        if let fileHandle = try? FileHandle(forWritingTo: logFileUrl) {
            process.standardOutput = fileHandle
            process.standardError = fileHandle
        } else {
            process.standardOutput = Pipe()
            process.standardError = Pipe()
        }
        
        do {
            try process.run()
            processes.append(process)
        } catch {
            print("Failed to start process \(executableURL.lastPathComponent): \(error)")
        }
    }
    
    func stopDaemons() {
        for process in processes {
            if process.isRunning {
                process.terminate()
            }
        }
        processes.removeAll()
        isRunning = false
    }
    
}

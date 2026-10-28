import Foundation
import AppKit

@MainActor
final class DaemonManager: ObservableObject {
    static let shared = DaemonManager()

    @Published private(set) var isRunning = false
    @Published private(set) var lastCaptureAt: Date?
    @Published private(set) var needsScreenPermission = false

    /// Directory that contains the Python backend (api.py, ingester.py, ...).
    private(set) var backendBasePath = ""

    private var processes: [Process] = []
    private var nativeDaemonTask: Task<Void, Never>?

    // MARK: - Backend location

    /// Resolve where the Python backend lives, in priority order:
    /// 1. User override in defaults ("BackendBasePath")
    /// 2. Inside the app bundle (fully portable installs)
    /// 3. The development repo in ~/Antigravity/SAKSHI/Mnemos
    static func resolveBackendPath() -> String {
        let fm = FileManager.default
        var candidates: [String] = []

        if let override = UserDefaults.standard.string(forKey: "BackendBasePath"), !override.isEmpty {
            candidates.append(override)
        }
        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent("mnemos-backend").path)
        }
        let home = fm.homeDirectoryForCurrentUser.path
        candidates.append("\(home)/Antigravity/SAKSHI/Mnemos/mnemos-backend")

        return candidates.first { fm.fileExists(atPath: "\($0)/api.py") } ?? ""
    }

    // MARK: - Lifecycle

    func toggleDaemons() {
        if isRunning { stopDaemons() } else { startDaemons() }
    }

    func startDaemons() {
        guard !isRunning else { return }

        // Kill any zombie processes from previous runs
        killExistingProcesses()

        backendBasePath = DaemonManager.resolveBackendPath()
        if backendBasePath.isEmpty {
            print("[SAKSHI] Could not locate the Python backend (api.py not found).")
        }

        // 1. Native Swift capture loop (runs inside the app process)
        startNativeDaemon()

        // 2-4. Python ingester, summarizer and FastAPI server
        let venvPython = "\(backendBasePath)/.venv/bin/python3"
        let hasVenv = FileManager.default.fileExists(atPath: venvPython)
        for (script, logName) in [("ingester.py", "ingester.log"),
                                  ("summarizer.py", "summarizer.log"),
                                  ("api.py", "api.log")] {
            startProcess(
                executableURL: URL(fileURLWithPath: hasVenv ? venvPython : "/usr/bin/python3"),
                arguments: [script],
                currentDirectory: URL(fileURLWithPath: backendBasePath),
                logFileName: logName
            )
        }

        isRunning = true
    }

    private func startNativeDaemon() {
        nativeDaemonTask?.cancel()
        nativeDaemonTask = Task.detached(priority: .utility) { [weak self] in
            let capture = ScreenCapture()
            let ocr = VisionOCR()

            while !Task.isCancelled {
                let frameTime = Date()

                // Attempt the capture regardless of preflight — some macOS
                // versions report stale permission state via CGPreflight.
                if let image = capture.captureFrame() {
                    if let text = await ocr.extractText(from: image) {
                        // AppKit APIs (frontmost app, AX window title) must run on the main actor
                        let metadata = await MainActor.run { MetadataFetcher.fetchCurrent() }
                        let payload = SpoolWriter.SpoolPayload(
                            timestamp: frameTime,
                            appName: metadata.appName,
                            windowTitle: metadata.windowTitle,
                            ocrText: text,
                            hasAudio: false,
                            audioFileName: nil
                        )
                        SpoolWriter.write(payload: payload, audioData: nil)
                        print("[SAKSHI] Captured frame (\(text.count) OCR chars) — \(metadata.appName)")
                        if text.isEmpty {
                            ScreenCapture.dumpFrame(image)
                        }
                        await self?.reportCapture(at: frameTime, characters: text.count)
                    } else {
                        await self?.reportCaptureSkipped()
                    }
                } else {
                    let hasPermission = CGPreflightScreenCaptureAccess()
                    if !hasPermission {
                        print("[SAKSHI] Screen Recording permission missing — prompting (System Settings → Privacy & Security → Screen Recording)")
                        CGRequestScreenCaptureAccess()
                        await self?.reportPermissionMissing(true)
                    } else {
                        print("[SAKSHI] Frame capture returned nil despite permission — check display state")
                        await self?.reportCaptureFailed()
                    }
                }

                let elapsed = Date().timeIntervalSince(frameTime)
                let interval = Config.captureInterval
                let remaining = interval - elapsed
                if remaining > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                }
            }
        }
    }

    // MARK: - Health reporting (main actor)

    private func reportCapture(at date: Date, characters: Int) {
        lastCaptureAt = date
        needsScreenPermission = false
    }

    private func reportCaptureSkipped() {
        lastCaptureAt = Date()
    }

    private func reportCaptureFailed() {
        // Keep lastCaptureAt unchanged; a single failure isn't fatal.
    }

    private func reportPermissionMissing(_ missing: Bool) {
        needsScreenPermission = missing
    }

    // MARK: - Process helpers

    /// Kill leftover processes from a previous app run to prevent port conflicts
    private func killExistingProcesses() {
        let patterns = ["ingester.py", "summarizer.py", "api.py", "mnemos-daemon"]
        var killedAny = false

        for pattern in patterns {
            if let pids = runProcessOutput("/usr/bin/pgrep", arguments: ["-f", pattern]),
               !pids.isEmpty {
                _ = runProcessOutput("/usr/bin/pkill", arguments: ["-f", pattern])
                killedAny = true
            }
        }

        if killedAny {
            // Give the OS time to release ports
            Thread.sleep(forTimeInterval: 1.0)
        }
    }

    private func runProcessOutput(_ executable: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
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

            // Auto-restart logic (with a short backoff to avoid hot loops)
            process.terminationHandler = { [weak self] terminatedProcess in
                DispatchQueue.main.async {
                    guard let self = self, self.isRunning else { return }
                    print("Process \(executableURL.lastPathComponent) exited unexpectedly. Restarting...")
                    self.processes.removeAll { $0 == terminatedProcess }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        guard self.isRunning else { return }
                        self.startProcess(executableURL: executableURL, arguments: arguments, currentDirectory: currentDirectory, logFileName: logFileName)
                    }
                }
            }
        } catch {
            print("Failed to start process \(executableURL.lastPathComponent): \(error)")
        }
    }

    func stopDaemons() {
        nativeDaemonTask?.cancel()
        nativeDaemonTask = nil

        for process in processes {
            if process.isRunning {
                process.terminate()
            }
        }

        // Grace period, then force-kill anything that ignored SIGTERM
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline && processes.contains(where: { $0.isRunning }) {
            Thread.sleep(forTimeInterval: 0.1)
        }
        for process in processes where process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }

        processes.removeAll()
        isRunning = false
    }
}

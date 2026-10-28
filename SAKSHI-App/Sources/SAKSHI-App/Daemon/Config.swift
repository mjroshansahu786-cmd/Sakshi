import Foundation

struct Config {
    /// Capture cadence. Read from defaults so Preferences can change it live
    /// (the native loop re-reads it on every iteration).
    static var captureInterval: TimeInterval {
        let value = UserDefaults.standard.double(forKey: "CaptureInterval")
        return value >= 15 ? value : 60.0
    }

    static let spoolDirectory: URL = {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".mnemos")
            .appendingPathComponent("spool")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()
}

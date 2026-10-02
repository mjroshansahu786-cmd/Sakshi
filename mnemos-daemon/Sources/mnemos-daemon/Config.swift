import Foundation

struct Config {
    static let captureInterval: TimeInterval = 60.0
    static let spoolDirectory: URL = {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".mnemos")
            .appendingPathComponent("spool")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()
}

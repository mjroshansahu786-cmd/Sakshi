import Foundation

class SpoolWriter {
    struct SpoolPayload: Codable {
        let timestamp: Date
        let appName: String
        let windowTitle: String
        let ocrText: String
        let hasAudio: Bool
        let audioFileName: String?
    }
    
    static func write(payload: SpoolPayload, audioData: Data?) {
        let formatter = ISO8601DateFormatter()
        let timeString = formatter.string(from: payload.timestamp)
        let safeTimeString = timeString.replacingOccurrences(of: ":", with: "-")
        
        var finalPayload = payload
        
        if let audio = audioData, !audio.isEmpty {
            let audioFilename = "\(safeTimeString).wav"
            let audioURL = Config.spoolDirectory.appendingPathComponent(audioFilename)
            do {
                try audio.write(to: audioURL)
                finalPayload = SpoolPayload(
                    timestamp: payload.timestamp,
                    appName: payload.appName,
                    windowTitle: payload.windowTitle,
                    ocrText: payload.ocrText,
                    hasAudio: true,
                    audioFileName: audioFilename
                )
            } catch {
                print("Failed to write audio: \(error)")
            }
        }
        
        let jsonFilename = "\(safeTimeString).json"
        let jsonURL = Config.spoolDirectory.appendingPathComponent(jsonFilename)
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(finalPayload)
            try data.write(to: jsonURL)
        } catch {
            print("Failed to write JSON: \(error)")
        }
    }
}

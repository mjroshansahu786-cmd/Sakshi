import Foundation

@main
struct MnemosDaemon {
    static func main() {
        print("Starting Mnemos Daemon...")
        print("Spool directory: \(Config.spoolDirectory.path)")
        fflush(stdout)
        
        Task {
            let screenCapture = ScreenCapture()
            let ocr = VisionOCR()
            
            while true {
                let start = Date()
                
                // 1. Capture screen
                print("[\(start)] Capturing frame...")
                fflush(stdout)
                
                if let image = screenCapture.captureFrame() {
                    print("[\(start)] Frame captured. Extracting text...")
                    fflush(stdout)
                    
                    // 2. OCR (skips if image is similar to previous)
                    if let text = await ocr.extractText(from: image) {
                        print("[\(start)] OCR extracted \(text.count) characters. Fetching metadata...")
                        fflush(stdout)
                        
                        // 3. Metadata
                        let metadata = MetadataFetcher.fetchCurrent()
                        
                        // 4. Write to spool
                        let payload = SpoolWriter.SpoolPayload(
                            timestamp: start,
                            appName: metadata.appName,
                            windowTitle: metadata.windowTitle,
                            ocrText: text,
                            hasAudio: false,
                            audioFileName: nil
                        )
                        
                        SpoolWriter.write(payload: payload, audioData: nil)
                        print("[\(start)] Saved frame for \(metadata.appName) (OCR: \(text.count) chars)")
                        fflush(stdout)
                    } else {
                        // Skipped due to static screen
                        print("[\(start)] Skipped - Static screen")
                        fflush(stdout)
                    }
                } else {
                    print("[\(start)] Failed to capture frame")
                    fflush(stdout)
                }
                
                // Wait for next interval
                let elapsed = Date().timeIntervalSince(start)
                let remaining = Config.captureInterval - elapsed
                if remaining > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                }
            }
        }
        
        RunLoop.main.run()
    }
}

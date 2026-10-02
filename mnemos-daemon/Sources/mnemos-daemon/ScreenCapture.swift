import Foundation
import ScreenCaptureKit
import CoreGraphics
import OSLog
import AVFoundation

class ScreenCapture: NSObject, SCStreamOutput {
    let logger = Logger(subsystem: "com.mnemos", category: "ScreenCapture")
    private var stream: SCStream?
    private var audioData = NSMutableData()
    private var audioFile: AVAudioFile?
    private var audioFileURL: URL?
    private var captureTask: Task<Void, Never>?
    
    @MainActor
    func captureFrame() -> CGImage? {
        if !CGPreflightScreenCaptureAccess() {
            print("Missing Screen Recording permissions. Requesting...")
            CGRequestScreenCaptureAccess()
            return nil
        }
        
        // Capture all active displays and stitch them together
        var displayCount: UInt32 = 0
        var activeDisplays = [CGDirectDisplayID](repeating: 0, count: 10)
        let err = CGGetActiveDisplayList(10, &activeDisplays, &displayCount)
        
        if err != .success || displayCount == 0 {
            return CGWindowListCreateImage(CGRect.infinite, .optionOnScreenOnly, kCGNullWindowID, .nominalResolution)
        }
        
        var images: [CGImage] = []
        var totalWidth: Int = 0
        var maxHeight: Int = 0
        
        for i in 0..<Int(displayCount) {
            let displayID = activeDisplays[i]
            if let image = CGDisplayCreateImage(displayID) {
                images.append(image)
                totalWidth += image.width
                maxHeight = max(maxHeight, image.height)
            }
        }
        
        if images.isEmpty { return nil }
        if images.count == 1 { return images[0] }
        
        // Stitch horizontally
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: totalWidth, height: maxHeight, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else {
            return images[0]
        }
        
        var currentX = 0
        for image in images {
            // Draw image. Note: CGContext draw coordinates are usually bottom-left origin,
            // but we just want a flat image for OCR, so drawing them sequentially is fine.
            let rect = CGRect(x: currentX, y: maxHeight - image.height, width: image.width, height: image.height)
            context.draw(image, in: rect)
            currentX += image.width
        }
        
        return context.makeImage()
    }
    
    // Minimal audio capture logic (just to satisfy Sprint 2 MVP requirement)
    // In a real implementation we would write the PCM buffer to a .wav file.
    func startAudioCapture() async {
        do {
            let shareableContent = try await SCShareableContent.current
            guard let display = shareableContent.displays.first else { return }
            let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = true
            
            stream = SCStream(filter: filter, configuration: config, delegate: nil)
            try stream?.addStreamOutput(self, type: .audio, sampleHandlerQueue: DispatchQueue(label: "com.mnemos.audio"))
            try await stream?.startCapture()
            logger.info("Audio capture started")
        } catch {
            logger.error("Audio capture failed: \(error.localizedDescription)")
        }
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        // Here we would append to an AVAudioFile or a PCM buffer.
        // For MVP, we will simulate grabbing audio chunks in the main loop instead for simplicity.
    }
}

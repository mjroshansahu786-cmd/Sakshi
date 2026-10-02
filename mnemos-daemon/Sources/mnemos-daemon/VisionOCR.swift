import Foundation
import Vision
import CoreGraphics
import Accelerate

class VisionOCR {
    private var lastHash: [UInt8]?
    
    func extractText(from image: CGImage) async -> String? {
        if isSimilar(to: image) {
            return nil // Skip OCR if screen is static
        }
        
        return await withCheckedContinuation { continuation in
            var resumed = false
            
            let request = VNRecognizeTextRequest { request, error in
                guard !resumed else { return }
                resumed = true
                
                guard let observations = request.results as? [VNRecognizedTextObservation], error == nil else {
                    continuation.resume(returning: "")
                    return
                }
                let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
                // Fallback in case perform completes without calling the completion handler
                if !resumed {
                    resumed = true
                    continuation.resume(returning: "")
                }
            } catch {
                if !resumed {
                    resumed = true
                    continuation.resume(returning: "")
                }
            }
        }
    }
    
    private func isSimilar(to image: CGImage) -> Bool {
        guard let currentHash = computeHash(for: image) else { return false }
        defer { lastHash = currentHash }
        
        guard let previousHash = lastHash else { return false }
        
        var diffCount = 0
        for i in 0..<currentHash.count {
            if abs(Int(currentHash[i]) - Int(previousHash[i])) > 10 { // Threshold for pixel diff
                diffCount += 1
            }
        }
        
        // If more than 5% of the small 16x16 pixels differ significantly, it's not similar
        let totalPixels = currentHash.count
        let percentDiff = Double(diffCount) / Double(totalPixels)
        print("Diff: \(percentDiff) (count: \(diffCount)/\(totalPixels))")
        return percentDiff < 0.05
    }
    
    private func computeHash(for image: CGImage) -> [UInt8]? {
        let width = 16
        let height = 16
        
        let colorSpace = CGColorSpaceCreateDeviceGray()
        var pixelData = [UInt8](repeating: 0, count: width * height)
        
        guard let context = CGContext(data: &pixelData,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: width,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            return nil
        }
        
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        return pixelData
    }
}

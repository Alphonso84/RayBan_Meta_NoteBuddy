//
//  GeminiFrameEncoder.swift
//  Smart Glasses
//
//  Encodes video frames from CMSampleBuffer to base64 JPEG for Gemini Live API
//  Supports both real-time streaming and buffered chunk mode (5-second intervals)
//

import AVFoundation
import CoreImage
import UIKit

class GeminiFrameEncoder {

    // MARK: - Properties

    private let context = CIContext(options: [.useSoftwareRenderer: false])
    private let compressionQuality: CGFloat
    private let targetSize: CGSize

    private var lastEncodedTime: CFTimeInterval = 0
    private let minimumInterval: CFTimeInterval  // 1/FPS

    private let encodingQueue = DispatchQueue(label: "com.smartglasses.gemini.frameEncoder",
                                               qos: .userInitiated)

    // Statistics
    private(set) var framesEncoded: Int = 0
    private(set) var framesSkipped: Int = 0

    // MARK: - Buffered Mode Properties

    /// Whether to buffer frames instead of sending immediately
    var isBufferedMode: Bool = true

    /// Interval for sending buffered frames (default: 5 seconds)
    var bufferInterval: TimeInterval = 5.0

    /// Maximum frames to keep in buffer (to limit memory usage)
    private let maxBufferSize: Int = 15

    /// Frame buffer for chunk mode
    private var frameBuffer: [String] = []
    private let bufferLock = NSLock()

    /// Timer for periodic buffer flush
    private var bufferTimer: Timer?

    /// Callback when buffer is ready to send
    var onBufferReady: (([String]) -> Void)?

    /// Last frame timestamp for representative frame selection
    private var lastBufferFlushTime: CFTimeInterval = 0

    // MARK: - Initialization

    /// Initialize with target FPS (2-4 recommended for balance of quality and cost)
    /// - Parameters:
    ///   - targetFPS: Target frames per second (default: 3)
    ///   - compressionQuality: JPEG compression quality 0-1 (default: 0.6)
    ///   - targetSize: Maximum frame size, maintains aspect ratio (default: 640x480)
    init(targetFPS: Double = 3,
         compressionQuality: CGFloat = 0.6,
         targetSize: CGSize = CGSize(width: 640, height: 480)) {
        self.minimumInterval = 1.0 / targetFPS
        self.compressionQuality = compressionQuality
        self.targetSize = targetSize
    }

    // MARK: - Public Methods

    /// Encode a sample buffer to base64 JPEG if enough time has passed
    /// Returns nil if frame should be skipped (rate limiting)
    /// - Parameter sampleBuffer: The video frame to encode
    /// - Returns: Base64 encoded JPEG string, or nil if skipped
    func encode(_ sampleBuffer: CMSampleBuffer) -> String? {
        let currentTime = CACurrentMediaTime()

        // Rate limiting - skip frame if not enough time has passed
        guard currentTime - lastEncodedTime >= minimumInterval else {
            framesSkipped += 1
            return nil
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("[GeminiEncoder] Failed to get pixel buffer from sample buffer")
            return nil
        }

        lastEncodedTime = currentTime

        // Convert to CIImage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        // Calculate scale to fit within target size while maintaining aspect ratio
        let originalSize = ciImage.extent.size
        let scaleX = targetSize.width / originalSize.width
        let scaleY = targetSize.height / originalSize.height
        let scale = min(scaleX, scaleY, 1.0)  // Don't upscale

        var processedImage = ciImage

        // Scale down if needed
        if scale < 1.0 {
            processedImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }

        // Render to CGImage
        guard let cgImage = context.createCGImage(processedImage, from: processedImage.extent) else {
            print("[GeminiEncoder] Failed to create CGImage")
            return nil
        }

        // Convert to JPEG
        let uiImage = UIImage(cgImage: cgImage)
        guard let jpegData = uiImage.jpegData(compressionQuality: compressionQuality) else {
            print("[GeminiEncoder] Failed to create JPEG data")
            return nil
        }

        framesEncoded += 1

        // Return base64 encoded string
        return jpegData.base64EncodedString()
    }

    /// Encode a UIImage to base64 JPEG (useful for testing or static images)
    /// - Parameter image: The image to encode
    /// - Returns: Base64 encoded JPEG string
    func encode(_ image: UIImage) -> String? {
        // Resize if needed
        let resizedImage: UIImage
        if image.size.width > targetSize.width || image.size.height > targetSize.height {
            resizedImage = resizeImage(image, to: targetSize)
        } else {
            resizedImage = image
        }

        guard let jpegData = resizedImage.jpegData(compressionQuality: compressionQuality) else {
            return nil
        }

        framesEncoded += 1
        return jpegData.base64EncodedString()
    }

    /// Async version that encodes on background queue
    /// - Parameters:
    ///   - sampleBuffer: The video frame to encode
    ///   - completion: Called with the base64 string or nil
    func encodeAsync(_ sampleBuffer: CMSampleBuffer, completion: @escaping (String?) -> Void) {
        encodingQueue.async { [weak self] in
            let result = self?.encode(sampleBuffer)
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    /// Reset rate limiting (call when starting new session)
    func reset() {
        lastEncodedTime = 0
        framesEncoded = 0
        framesSkipped = 0
        clearBuffer()
        lastBufferFlushTime = 0
    }

    /// Get encoding statistics
    var statistics: (encoded: Int, skipped: Int, ratio: Double) {
        let total = framesEncoded + framesSkipped
        let ratio = total > 0 ? Double(framesEncoded) / Double(total) : 0
        return (framesEncoded, framesSkipped, ratio)
    }

    // MARK: - Buffered Mode Methods

    /// Start the buffer timer for periodic chunk sending
    func startBufferTimer() {
        stopBufferTimer()
        lastBufferFlushTime = CACurrentMediaTime()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.bufferTimer = Timer.scheduledTimer(withTimeInterval: self.bufferInterval, repeats: true) { [weak self] _ in
                self?.flushBuffer()
            }
        }
        print("[GeminiEncoder] Buffer timer started with \(bufferInterval)s interval")
    }

    /// Stop the buffer timer
    func stopBufferTimer() {
        bufferTimer?.invalidate()
        bufferTimer = nil
    }

    /// Add a frame to the buffer (in buffered mode)
    /// - Parameter sampleBuffer: The video frame to buffer
    /// - Returns: true if frame was added, false if skipped
    @discardableResult
    func bufferFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        let currentTime = CACurrentMediaTime()

        // Rate limiting - still apply FPS limit even in buffer mode
        guard currentTime - lastEncodedTime >= minimumInterval else {
            framesSkipped += 1
            return false
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("[GeminiEncoder] Failed to get pixel buffer from sample buffer")
            return false
        }

        lastEncodedTime = currentTime

        // Convert to CIImage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        // Calculate scale to fit within target size while maintaining aspect ratio
        let originalSize = ciImage.extent.size
        let scaleX = targetSize.width / originalSize.width
        let scaleY = targetSize.height / originalSize.height
        let scale = min(scaleX, scaleY, 1.0)  // Don't upscale

        var processedImage = ciImage

        // Scale down if needed
        if scale < 1.0 {
            processedImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }

        // Render to CGImage
        guard let cgImage = context.createCGImage(processedImage, from: processedImage.extent) else {
            print("[GeminiEncoder] Failed to create CGImage")
            return false
        }

        // Convert to JPEG
        let uiImage = UIImage(cgImage: cgImage)
        guard let jpegData = uiImage.jpegData(compressionQuality: compressionQuality) else {
            print("[GeminiEncoder] Failed to create JPEG data")
            return false
        }

        let base64String = jpegData.base64EncodedString()

        // Add to buffer with size limit
        bufferLock.lock()
        frameBuffer.append(base64String)
        if frameBuffer.count > maxBufferSize {
            // Remove oldest frames if buffer exceeds limit
            frameBuffer.removeFirst(frameBuffer.count - maxBufferSize)
        }
        bufferLock.unlock()

        framesEncoded += 1
        return true
    }

    /// Flush the buffer and return accumulated frames
    /// - Returns: Array of base64 encoded frames
    func flushBuffer() {
        bufferLock.lock()
        let frames = frameBuffer
        frameBuffer.removeAll()
        bufferLock.unlock()

        lastBufferFlushTime = CACurrentMediaTime()

        if !frames.isEmpty {
            print("[GeminiEncoder] Flushing buffer with \(frames.count) frames")
            onBufferReady?(frames)
        }
    }

    /// Clear the buffer without sending
    func clearBuffer() {
        bufferLock.lock()
        frameBuffer.removeAll()
        bufferLock.unlock()
    }

    /// Get current buffer size
    var currentBufferSize: Int {
        bufferLock.lock()
        let size = frameBuffer.count
        bufferLock.unlock()
        return size
    }

    // MARK: - Private Methods

    private func resizeImage(_ image: UIImage, to targetSize: CGSize) -> UIImage {
        let size = image.size
        let widthRatio = targetSize.width / size.width
        let heightRatio = targetSize.height / size.height
        let ratio = min(widthRatio, heightRatio)

        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)

        UIGraphicsBeginImageContextWithOptions(newSize, true, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return newImage ?? image
    }
}

// MARK: - Frame Encoding Configuration

extension GeminiFrameEncoder {

    /// Preset configurations for different use cases
    enum Preset {
        case lowBandwidth   // 2 FPS, 50% quality, 480x360
        case balanced       // 3 FPS, 60% quality, 640x480
        case highQuality    // 4 FPS, 70% quality, 800x600

        var targetFPS: Double {
            switch self {
            case .lowBandwidth: return 2
            case .balanced: return 3
            case .highQuality: return 4
            }
        }

        var compressionQuality: CGFloat {
            switch self {
            case .lowBandwidth: return 0.5
            case .balanced: return 0.6
            case .highQuality: return 0.7
            }
        }

        var targetSize: CGSize {
            switch self {
            case .lowBandwidth: return CGSize(width: 480, height: 360)
            case .balanced: return CGSize(width: 640, height: 480)
            case .highQuality: return CGSize(width: 800, height: 600)
            }
        }
    }

    /// Create encoder with preset configuration
    convenience init(preset: Preset) {
        self.init(
            targetFPS: preset.targetFPS,
            compressionQuality: preset.compressionQuality,
            targetSize: preset.targetSize
        )
    }
}

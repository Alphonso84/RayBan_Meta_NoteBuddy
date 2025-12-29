//
//  ObjectDetectionProcessor.swift
//  Smart Glasses
//
//  Created by Alphonso Sensley II on 12/9/25.
//

import Foundation
import Vision
import CoreImage
import AVFoundation
import Combine
import UIKit

/// Processes video frames using Apple's Vision framework for object tracking
/// Uses attention-based saliency to detect and track visually interesting regions
@MainActor
class ObjectDetectionProcessor: ObservableObject, DetectionConfigurable {

    // MARK: - Published Properties

    /// Latest detection result for UI binding
    @Published var latestResult: DetectionResult?

    /// Whether a frame is currently being processed
    @Published var isProcessing: Bool = false

    /// Error message if processing fails
    @Published var errorMessage: String?

    /// Whether manual (tap-to-select) tracking is active
    @Published var isManualTracking: Bool = false

    // MARK: - Manual Tracking State

    /// The observation being tracked (updated each frame)
    private var currentTrackingObservation: VNDetectedObjectObservation?

    /// Sequence request handler for stateful tracking across frames
    /// CRITICAL: Must be reused across frames for VNTrackObjectRequest
    private var sequenceRequestHandler: VNSequenceRequestHandler?

    /// Initial bounding box size when user taps (as fraction of frame)
    private let initialTapBoxSize: CGFloat = 0.15  // 15% of frame

    // MARK: - Configuration

    /// Detection configuration settings
    var configuration = DetectionConfiguration.default

    /// Minimum saliency threshold for detecting objects (0-1)
    var saliencyThreshold: Float = 0.3

    /// Minimum bounding box size (as fraction of frame)
    var minimumBoxSize: CGFloat = 0.05

    // MARK: - Private Properties

    /// Frame counter for skip logic
    private var frameCounter: Int = 0

    /// Dedicated queue for Vision processing
    private let processingQueue = DispatchQueue(
        label: "com.smartglasses.objecttracking",
        qos: .userInitiated
    )

    /// CIContext for image processing
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Colors for tracked objects
    private let trackingColors: [UIColor] = [
        .systemCyan, .systemMint, .systemPink, .systemOrange,
        .systemYellow, .systemPurple, .systemTeal, .systemIndigo
    ]

    // MARK: - Public Methods

    /// Process a video frame for object tracking
    /// Routes to either manual tracking or saliency detection based on current mode
    /// - Parameter sampleBuffer: The CMSampleBuffer from the video stream
    func processFrame(_ sampleBuffer: CMSampleBuffer) {
        frameCounter += 1

        // Skip frames based on configuration
        guard frameCounter % configuration.frameSkipCount == 0 else { return }

        // Don't start new processing if still working on previous frame
        guard !isProcessing else { return }

        isProcessing = true
        let startTime = Date()

        processingQueue.async { [weak self] in
            guard let self = self else { return }

            // Extract pixel buffer from sample buffer
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                Task { @MainActor in
                    self.isProcessing = false
                    self.errorMessage = "Failed to get pixel buffer"
                }
                return
            }

            // Branch based on tracking mode
            if self.isManualTracking {
                self.processManualTracking(pixelBuffer: pixelBuffer, startTime: startTime)
            } else {
                self.processSaliencyDetection(pixelBuffer: pixelBuffer, startTime: startTime)
            }
        }
    }

    /// Process frame using VNTrackObjectRequest for manual tracking
    private func processManualTracking(pixelBuffer: CVPixelBuffer, startTime: Date) {
        guard let observation = currentTrackingObservation,
              let handler = sequenceRequestHandler else {
            Task { @MainActor in
                self.isProcessing = false
                self.stopManualTracking()
            }
            return
        }

        // Create tracking request
        let trackingRequest = VNTrackObjectRequest(detectedObjectObservation: observation) { [weak self] request, error in
            guard let self = self else { return }

            if let error = error {
                print("Tracking error: \(error.localizedDescription)")
                Task { @MainActor in
                    self.handleTrackingLoss()
                }
                return
            }

            // Get updated observation
            guard let results = request.results as? [VNDetectedObjectObservation],
                  let updatedObservation = results.first else {
                Task { @MainActor in
                    self.handleTrackingLoss()
                }
                return
            }

            // Check tracking confidence - if too low, tracking may be lost
            if updatedObservation.confidence < 0.3 {
                Task { @MainActor in
                    self.handleTrackingLoss()
                }
                return
            }

            // Update observation for next frame and publish result
            Task { @MainActor in
                self.currentTrackingObservation = updatedObservation

                let processingTime = Date().timeIntervalSince(startTime) * 1000
                let trackedObject = TrackedObject(
                    boundingBox: updatedObservation.boundingBox,
                    saliency: updatedObservation.confidence,
                    trackingLabel: "Tracking",
                    colorIndex: 0
                )

                self.latestResult = DetectionResult(
                    manuallyTrackedObject: trackedObject,
                    timestamp: Date(),
                    processingTimeMs: processingTime
                )
                self.isProcessing = false
            }
        }

        // Set tracking level for better accuracy
        trackingRequest.trackingLevel = .accurate

        do {
            // IMPORTANT: Use perform() on sequenceRequestHandler, not a new VNImageRequestHandler
            try handler.perform([trackingRequest], on: pixelBuffer, orientation: .up)
        } catch {
            print("Failed to perform tracking: \(error)")
            Task { @MainActor in
                self.handleTrackingLoss()
            }
        }
    }

    /// Process frame using saliency detection (auto-detection mode)
    private func processSaliencyDetection(pixelBuffer: CVPixelBuffer, startTime: Date) {
        // Create Vision request handler
        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .up,
            options: [:]
        )

        // Create saliency request for attention-based detection
        let saliencyRequest = VNGenerateAttentionBasedSaliencyImageRequest()

        do {
            // Perform saliency detection
            try handler.perform([saliencyRequest])

            // Extract salient regions from the result
            let trackedObjects = self.extractSalientRegions(from: saliencyRequest)

            // Process and publish results
            Task { @MainActor in
                let processingTime = Date().timeIntervalSince(startTime) * 1000
                self.latestResult = DetectionResult(
                    trackedObjects: trackedObjects,
                    timestamp: Date(),
                    processingTimeMs: processingTime
                )
                self.isProcessing = false
                self.errorMessage = nil
            }
        } catch {
            print("Vision processing error: \(error.localizedDescription)")
            Task { @MainActor in
                self.isProcessing = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    /// Reset the processor state
    func reset() {
        frameCounter = 0
        latestResult = nil
        isProcessing = false
        errorMessage = nil
        stopManualTracking()
    }

    // MARK: - Manual Tracking Methods

    /// Initialize manual tracking from a tap point
    /// - Parameter point: Normalized point in Vision coordinates (0-1, bottom-left origin)
    func startManualTracking(at point: CGPoint) {
        // Create initial bounding box centered on tap point
        let boxSize = initialTapBoxSize
        let initialBox = CGRect(
            x: max(0, point.x - boxSize / 2),
            y: max(0, point.y - boxSize / 2),
            width: min(boxSize, 1 - max(0, point.x - boxSize / 2)),
            height: min(boxSize, 1 - max(0, point.y - boxSize / 2))
        )

        // Create VNDetectedObjectObservation from bounding box
        let observation = VNDetectedObjectObservation(boundingBox: initialBox)

        // Initialize tracking
        initializeTracking(with: observation)
    }

    /// Initialize tracking with a VNDetectedObjectObservation
    /// - Parameter observation: The observation to track
    private func initializeTracking(with observation: VNDetectedObjectObservation) {
        currentTrackingObservation = observation
        sequenceRequestHandler = VNSequenceRequestHandler()
        isManualTracking = true

        // Create initial result to show immediately
        let trackedObject = TrackedObject(
            boundingBox: observation.boundingBox,
            saliency: 1.0,  // Manual selection = highest priority
            trackingLabel: "Tracking",
            colorIndex: 0  // Use first color (cyan)
        )

        latestResult = DetectionResult(
            manuallyTrackedObject: trackedObject,
            timestamp: Date(),
            processingTimeMs: 0
        )
    }

    /// Stop manual tracking and return to auto-detection
    func stopManualTracking() {
        isManualTracking = false
        currentTrackingObservation = nil
        sequenceRequestHandler = nil
        // Don't clear latestResult here - let auto-detection fill it
    }

    /// Handle tracking loss - notify user and return to auto-detection
    private func handleTrackingLoss() {
        stopManualTracking()
        errorMessage = "Tracking lost - tap to select again"
        isProcessing = false

        // Clear error after delay
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                if self.errorMessage == "Tracking lost - tap to select again" {
                    self.errorMessage = nil
                }
            }
        }
    }

    // MARK: - Private Methods

    /// Extract salient regions from saliency request result
    private func extractSalientRegions(from request: VNGenerateAttentionBasedSaliencyImageRequest) -> [TrackedObject] {
        guard let results = request.results,
              let observation = results.first as? VNSaliencyImageObservation else {
            return []
        }

        // Get salient objects (regions of interest)
        guard let salientObjects = observation.salientObjects else {
            return []
        }

        var trackedObjects: [TrackedObject] = []

        for (index, salientObject) in salientObjects.enumerated() {
            let boundingBox = salientObject.boundingBox

            // Filter out very small boxes
            guard boundingBox.width >= minimumBoxSize && boundingBox.height >= minimumBoxSize else {
                continue
            }

            // Calculate saliency score based on bounding box confidence
            let saliency = salientObject.confidence

            // Filter by saliency threshold
            guard saliency >= saliencyThreshold else {
                continue
            }

            // Limit to max detections
            guard trackedObjects.count < configuration.maxDetections else {
                break
            }

            let trackedObject = TrackedObject(
                boundingBox: boundingBox,
                saliency: saliency,
                trackingLabel: "Object \(index + 1)",
                colorIndex: index % trackingColors.count
            )

            trackedObjects.append(trackedObject)
        }

        // Sort by saliency (most salient first)
        return trackedObjects.sorted { $0.saliency > $1.saliency }
    }
}

// MARK: - Legacy Classification Support
extension ObjectDetectionProcessor {

    /// Process frame using image classification (legacy mode)
    /// This uses VNClassifyImageRequest for classification with labels
    func processFrameWithClassification(_ sampleBuffer: CMSampleBuffer) {
        frameCounter += 1

        guard frameCounter % configuration.frameSkipCount == 0 else { return }
        guard !isProcessing else { return }

        isProcessing = true
        let startTime = Date()

        processingQueue.async { [weak self] in
            guard let self = self else { return }

            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                Task { @MainActor in
                    self.isProcessing = false
                }
                return
            }

            let handler = VNImageRequestHandler(
                cvPixelBuffer: pixelBuffer,
                orientation: .up,
                options: [:]
            )

            let classificationRequest = VNClassifyImageRequest { request, error in
                guard error == nil,
                      let observations = request.results as? [VNClassificationObservation] else {
                    return
                }

                let objects = observations
                    .filter { $0.confidence >= self.configuration.confidenceThreshold }
                    .prefix(self.configuration.maxDetections)
                    .map { observation -> DetectedObject in
                        let centerBox = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
                        let label = observation.identifier
                            .replacingOccurrences(of: "_", with: " ")
                            .capitalized

                        return DetectedObject(
                            label: label,
                            confidence: observation.confidence,
                            boundingBox: centerBox,
                            isInFocusArea: true
                        )
                    }

                Task { @MainActor in
                    let processingTime = Date().timeIntervalSince(startTime) * 1000
                    self.latestResult = DetectionResult(
                        objects: Array(objects),
                        timestamp: Date(),
                        processingTimeMs: processingTime
                    )
                    self.isProcessing = false
                }
            }

            do {
                try handler.perform([classificationRequest])
            } catch {
                print("Classification error: \(error)")
                Task { @MainActor in
                    self.isProcessing = false
                }
            }
        }
    }
}

// MARK: - Helper Methods
extension ObjectDetectionProcessor {

    /// Format a label identifier for display
    /// - Parameter identifier: Raw identifier (e.g., "golden_retriever")
    /// - Returns: Human-readable label (e.g., "Golden Retriever")
    func formatLabel(_ identifier: String) -> String {
        identifier
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}

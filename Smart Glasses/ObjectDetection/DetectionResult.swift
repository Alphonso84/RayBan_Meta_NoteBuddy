//
//  DetectionResult.swift
//  Smart Glasses
//
//  Created by Alphonso Sensley II on 12/9/25.
//

import Foundation
import CoreGraphics

// MARK: - Tracked Object
/// Represents a tracked object in a video frame (no classification, just bounding box)
struct TrackedObject: Identifiable, Equatable {
    let id = UUID()

    /// Bounding box in normalized coordinates (0-1)
    /// Note: Vision uses bottom-left origin, this is stored as-is
    let boundingBox: CGRect

    /// Saliency/attention score from 0-1 (how "interesting" this region is)
    let saliency: Float

    /// Generic label for display (e.g., "Object 1", "Object 2")
    let trackingLabel: String

    /// Color index for visual distinction between tracked objects
    let colorIndex: Int

    static func == (lhs: TrackedObject, rhs: TrackedObject) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Detected Object (Legacy - for classification mode)
/// Represents a single detected object in a video frame
struct DetectedObject: Identifiable, Equatable {
    let id = UUID()

    /// The classification label (e.g., "cat", "person", "cup")
    let label: String

    /// Confidence score from 0-1
    let confidence: Float

    /// Bounding box in normalized coordinates (0-1)
    /// Note: Vision uses bottom-left origin, this is stored as-is
    let boundingBox: CGRect

    /// Whether this object is within the focus area
    let isInFocusArea: Bool

    /// Display-friendly label with confidence percentage
    var displayLabel: String {
        "\(label) (\(Int(confidence * 100))%)"
    }

    /// Confidence as a percentage string
    var confidencePercent: String {
        "\(Int(confidence * 100))%"
    }

    static func == (lhs: DetectedObject, rhs: DetectedObject) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Detection Result
/// Contains all detection/tracking results for a single frame
struct DetectionResult {
    /// All detected objects in the frame (classification mode)
    let objects: [DetectedObject]

    /// All tracked objects in the frame (tracking mode)
    let trackedObjects: [TrackedObject]

    /// Timestamp when this detection was performed
    let timestamp: Date

    /// Time taken to process the frame in milliseconds
    let processingTimeMs: Double

    /// Whether this is manual tap-to-track mode (single selected object) vs auto-saliency
    let isManualTrackingMode: Bool

    /// Whether this result is from tracking mode (vs classification mode)
    var isTrackingMode: Bool {
        !trackedObjects.isEmpty
    }

    /// Objects that are within the focus area, sorted by confidence
    var focusedObjects: [DetectedObject] {
        objects
            .filter { $0.isInFocusArea }
            .sorted { $0.confidence > $1.confidence }
    }

    /// Objects outside the focus area
    var unfocusedObjects: [DetectedObject] {
        objects.filter { !$0.isInFocusArea }
    }

    /// The primary (highest confidence) object in the focus area
    var primaryObject: DetectedObject? {
        focusedObjects.first
    }

    /// Whether any objects were detected in the focus area
    var hasFocusedObjects: Bool {
        !focusedObjects.isEmpty
    }

    /// Total number of detections (both modes)
    var count: Int {
        isTrackingMode ? trackedObjects.count : objects.count
    }

    /// Convenience initializer for classification mode
    init(objects: [DetectedObject], timestamp: Date, processingTimeMs: Double) {
        self.objects = objects
        self.trackedObjects = []
        self.timestamp = timestamp
        self.processingTimeMs = processingTimeMs
        self.isManualTrackingMode = false
    }

    /// Initializer for auto-saliency tracking mode
    init(trackedObjects: [TrackedObject], timestamp: Date, processingTimeMs: Double) {
        self.objects = []
        self.trackedObjects = trackedObjects
        self.timestamp = timestamp
        self.processingTimeMs = processingTimeMs
        self.isManualTrackingMode = false
    }

    /// Initializer for manual tap-to-track mode (single selected object)
    init(manuallyTrackedObject: TrackedObject, timestamp: Date, processingTimeMs: Double) {
        self.objects = []
        self.trackedObjects = [manuallyTrackedObject]
        self.timestamp = timestamp
        self.processingTimeMs = processingTimeMs
        self.isManualTrackingMode = true
    }

    /// Empty result
    static let empty = DetectionResult(
        objects: [],
        timestamp: Date(),
        processingTimeMs: 0
    )
}

// MARK: - Detection Result Description
extension DetectionResult {
    /// Generate a natural language description of what was detected/tracked
    func generateDescription() -> String {
        // Tracking mode description
        if isTrackingMode {
            if trackedObjects.isEmpty {
                return "No objects detected"
            }

            if trackedObjects.count == 1 {
                return "Tracking 1 object"
            }

            return "Tracking \(trackedObjects.count) objects"
        }

        // Classification mode description
        let focused = focusedObjects

        if focused.isEmpty {
            return "No objects detected in focus area"
        }

        if focused.count == 1 {
            return "I see a \(focused[0].label)"
        }

        if focused.count == 2 {
            return "I see a \(focused[0].label) and a \(focused[1].label)"
        }

        // For 3+ objects, list first few and summarize
        let labels = focused.prefix(3).map { $0.label }
        let lastLabel = labels.last!
        let otherLabels = labels.dropLast().joined(separator: ", ")

        if focused.count > 3 {
            return "I see \(otherLabels), \(lastLabel), and \(focused.count - 3) more objects"
        }

        return "I see \(otherLabels), and \(lastLabel)"
    }
}

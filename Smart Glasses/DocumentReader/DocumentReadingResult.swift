//
//  DocumentReadingResult.swift
//  Smart Glasses
//
//  Created by Claude on 1/20/26.
//

import Foundation
import CoreGraphics
import UIKit

// MARK: - Recognized Text Block

/// Represents a single recognized text region
struct RecognizedTextBlock: Identifiable, Equatable {
    let id: UUID
    let text: String
    let boundingBox: CGRect  // Vision coordinates (0-1, bottom-left origin)
    let confidence: Float

    init(id: UUID = UUID(), text: String, boundingBox: CGRect, confidence: Float) {
        self.id = id
        self.text = text
        self.boundingBox = boundingBox
        self.confidence = confidence
    }
}

// MARK: - Document Boundary
/// Represents the detected document boundary in the frame
struct DocumentBoundary: Equatable {
    /// The four corners of the document in Vision coordinates (0-1, bottom-left origin)
    /// Order: top-left, top-right, bottom-right, bottom-left
    let topLeft: CGPoint
    let topRight: CGPoint
    let bottomRight: CGPoint
    let bottomLeft: CGPoint

    /// Confidence of the document detection (0-1)
    let confidence: Float

    /// Convert to a path for drawing
    func path(in size: CGSize) -> [CGPoint] {
        // Convert Vision coordinates to SwiftUI coordinates
        return [
            CGPoint(x: topLeft.x * size.width, y: (1 - topLeft.y) * size.height),
            CGPoint(x: topRight.x * size.width, y: (1 - topRight.y) * size.height),
            CGPoint(x: bottomRight.x * size.width, y: (1 - bottomRight.y) * size.height),
            CGPoint(x: bottomLeft.x * size.width, y: (1 - bottomLeft.y) * size.height)
        ]
    }

    /// Bounding rect containing the document
    var boundingRect: CGRect {
        let minX = min(topLeft.x, bottomLeft.x)
        let maxX = max(topRight.x, bottomRight.x)
        let minY = min(bottomLeft.y, bottomRight.y)
        let maxY = max(topLeft.y, topRight.y)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

// MARK: - Document Reading Result
/// Contains the result of document detection and OCR
struct DocumentReadingResult: Equatable {
    static func == (lhs: DocumentReadingResult, rhs: DocumentReadingResult) -> Bool {
        lhs.documentBoundary == rhs.documentBoundary &&
        lhs.extractedText == rhs.extractedText &&
        lhs.textBlocks == rhs.textBlocks &&
        lhs.timestamp == rhs.timestamp
    }

    /// The detected document boundary (nil if no document detected)
    let documentBoundary: DocumentBoundary?

    /// The perspective-corrected document image
    let correctedImage: UIImage?

    /// The extracted text from the document
    let extractedText: String

    /// Individual text blocks with positions (relative to corrected image)
    let textBlocks: [RecognizedTextBlock]

    /// Timestamp when this reading was performed
    let timestamp: Date

    /// Time taken to process in milliseconds
    let processingTimeMs: Double

    /// Whether a document was detected
    var hasDocument: Bool {
        documentBoundary != nil
    }

    /// Whether any text was extracted
    var hasText: Bool {
        !extractedText.isEmpty
    }

    /// Number of text blocks
    var textBlockCount: Int {
        textBlocks.count
    }

    /// Empty result (no document detected)
    static let empty = DocumentReadingResult(
        documentBoundary: nil,
        correctedImage: nil,
        extractedText: "",
        textBlocks: [],
        timestamp: Date(),
        processingTimeMs: 0
    )

    /// Check if text has changed significantly from another result
    func hasTextChanged(from other: DocumentReadingResult?) -> Bool {
        guard let other = other else { return hasText }

        // Simple comparison - could be made more sophisticated
        let currentNormalized = extractedText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let otherNormalized = other.extractedText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Consider changed if more than 10% different
        if currentNormalized.isEmpty && otherNormalized.isEmpty {
            return false
        }

        if currentNormalized.isEmpty || otherNormalized.isEmpty {
            return true
        }

        // Simple length-based change detection
        let lengthDiff = abs(currentNormalized.count - otherNormalized.count)
        let maxLength = max(currentNormalized.count, otherNormalized.count)
        let changeRatio = Double(lengthDiff) / Double(maxLength)

        return changeRatio > 0.1 || currentNormalized != otherNormalized
    }
}

// MARK: - Document Reader State
/// State of the document reader
enum DocumentReaderState: Equatable {
    case idle
    case scanning
    case detectingDocument
    case processingDocument
    case documentDetected
    case readingText
    case reading
    case complete
    case error(String)

    var description: String {
        switch self {
        case .idle:
            return "Ready"
        case .scanning:
            return "Scanning..."
        case .detectingDocument:
            return "Detecting..."
        case .processingDocument:
            return "Processing..."
        case .documentDetected:
            return "Document Found"
        case .readingText:
            return "Reading Text..."
        case .reading:
            return "Reading..."
        case .complete:
            return "Complete"
        case .error(let message):
            return message
        }
    }
}

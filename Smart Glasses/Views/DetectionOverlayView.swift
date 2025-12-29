//
//  DetectionOverlayView.swift
//  Smart Glasses
//
//  Created by Alphonso Sensley II on 12/9/25.
//

import SwiftUI

/// Overlay view that displays tracking/detection results on top of the video feed
struct DetectionOverlayView: View {
    let result: DetectionResult?
    var onClearSelection: (() -> Void)? = nil

    /// Colors for tracked objects
    private let trackingColors: [Color] = [
        .cyan, .mint, .pink, .orange,
        .yellow, .purple, .teal, .indigo
    ]

    init(result: DetectionResult?, onClearSelection: (() -> Void)? = nil) {
        self.result = result
        self.onClearSelection = onClearSelection
    }

    // Legacy initializer for compatibility
    init(
        result: DetectionResult?,
        focusArea: FocusArea = .center,
        showFocusArea: Bool = true
    ) {
        self.result = result
        self.onClearSelection = nil
        // Focus area parameters are now ignored - tracking uses full frame
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Manual tracking mode: show single tracked object with special styling
                if let result = result, result.isManualTrackingMode {
                    ForEach(result.trackedObjects) { trackedObject in
                        ManualTrackingBoxView(
                            trackedObject: trackedObject,
                            containerSize: geometry.size
                        )
                    }

                    // "Tracking Locked" indicator and clear button at top
                    VStack {
                        HStack {
                            // Tracking locked indicator
                            HStack(spacing: 6) {
                                Image(systemName: "scope")
                                    .font(.caption)
                                Text("Tracking Locked")
                                    .font(.caption)
                                    .fontWeight(.bold)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.green.opacity(0.8))
                            .clipShape(Capsule())

                            Spacer()

                            // Clear selection button
                            if let onClear = onClearSelection {
                                Button {
                                    onClear()
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.caption)
                                        Text("Clear")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                    }
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.red.opacity(0.8))
                                    .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 60)

                        Spacer()
                    }
                }

                // Auto saliency tracking mode: show tracked objects
                else if let result = result, result.isTrackingMode {
                    ForEach(result.trackedObjects) { trackedObject in
                        TrackingBoxView(
                            trackedObject: trackedObject,
                            containerSize: geometry.size,
                            color: trackingColors[trackedObject.colorIndex % trackingColors.count]
                        )
                    }

                    // Tracking count badge
                    if !result.trackedObjects.isEmpty {
                        TrackingBadge(count: result.trackedObjects.count)
                            .position(
                                x: geometry.size.width - 50,
                                y: 30
                            )
                    }
                }

                // Classification mode: show detected objects (legacy)
                if let result = result, !result.isTrackingMode {
                    ForEach(result.objects) { object in
                        BoundingBoxView(
                            object: object,
                            containerSize: geometry.size
                        )
                    }

                    if result.hasFocusedObjects {
                        DetectionBadge(count: result.focusedObjects.count)
                            .position(
                                x: geometry.size.width - 50,
                                y: 30
                            )
                    }
                }
            }
        }
        .allowsHitTesting(onClearSelection != nil) // Enable hit testing only when clear button is available
    }
}

// MARK: - Tracking Box View
/// Displays a bounding box around a tracked object (no label, just colored box)
struct TrackingBoxView: View {
    let trackedObject: TrackedObject
    let containerSize: CGSize
    let color: Color

    /// Convert Vision coordinates (bottom-left origin) to SwiftUI (top-left origin)
    private var displayRect: CGRect {
        let box = trackedObject.boundingBox
        return CGRect(
            x: box.origin.x * containerSize.width,
            y: (1 - box.origin.y - box.height) * containerSize.height,
            width: box.width * containerSize.width,
            height: box.height * containerSize.height
        )
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Bounding box rectangle with animated border
            RoundedRectangle(cornerRadius: 6)
                .stroke(color, lineWidth: 3)
                .frame(width: displayRect.width, height: displayRect.height)
                .shadow(color: color.opacity(0.5), radius: 4)

            // Small label tag with object number
            Text(trackedObject.trackingLabel)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .offset(y: -24)
        }
        .position(x: displayRect.midX, y: displayRect.midY)
    }
}

// MARK: - Tracking Badge
/// Shows count of tracked objects
struct TrackingBadge: View {
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "scope")
                .font(.caption)
            Text("\(count)")
                .font(.caption)
                .fontWeight(.bold)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.cyan.opacity(0.8))
        .clipShape(Capsule())
    }
}

// MARK: - Manual Tracking Box View
/// Displays a bounding box for manually selected object with animated green corners
struct ManualTrackingBoxView: View {
    let trackedObject: TrackedObject
    let containerSize: CGSize

    /// Convert Vision coordinates (bottom-left origin) to SwiftUI (top-left origin)
    private var displayRect: CGRect {
        let box = trackedObject.boundingBox
        return CGRect(
            x: box.origin.x * containerSize.width,
            y: (1 - box.origin.y - box.height) * containerSize.height,
            width: box.width * containerSize.width,
            height: box.height * containerSize.height
        )
    }

    var body: some View {
        ZStack {
            // Animated corner brackets
            TrackingCorners(rect: displayRect)

            // Crosshair at center
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .light))
                .foregroundColor(.green.opacity(0.8))
                .position(x: displayRect.midX, y: displayRect.midY)
        }
    }
}

// MARK: - Tracking Corners
/// Animated corner brackets for manual tracking selection
struct TrackingCorners: View {
    let rect: CGRect
    let cornerLength: CGFloat = 24
    let lineWidth: CGFloat = 3

    @State private var isAnimating = false

    var body: some View {
        let color = Color.green

        ZStack {
            // Top-left corner
            Path { path in
                path.move(to: CGPoint(x: rect.minX, y: rect.minY + cornerLength))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.minX + cornerLength, y: rect.minY))
            }
            .stroke(color, lineWidth: lineWidth)

            // Top-right corner
            Path { path in
                path.move(to: CGPoint(x: rect.maxX - cornerLength, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cornerLength))
            }
            .stroke(color, lineWidth: lineWidth)

            // Bottom-left corner
            Path { path in
                path.move(to: CGPoint(x: rect.minX, y: rect.maxY - cornerLength))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX + cornerLength, y: rect.maxY))
            }
            .stroke(color, lineWidth: lineWidth)

            // Bottom-right corner
            Path { path in
                path.move(to: CGPoint(x: rect.maxX - cornerLength, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerLength))
            }
            .stroke(color, lineWidth: lineWidth)
        }
        .shadow(color: color.opacity(0.6), radius: isAnimating ? 8 : 4)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

// MARK: - Focus Area Overlay
/// Displays the focus area rectangle
struct FocusAreaOverlay: View {
    let focusArea: FocusArea
    let size: CGSize

    private var rect: CGRect {
        CGRect(
            x: focusArea.origin.x * size.width,
            y: focusArea.origin.y * size.height,
            width: focusArea.size.width * size.width,
            height: focusArea.size.height * size.height
        )
    }

    var body: some View {
        ZStack {
            // Corner brackets instead of full rectangle
            FocusCorners(rect: rect)

            // "FOCUS" label
            Text("FOCUS")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.yellow.opacity(0.8))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .position(x: rect.midX, y: rect.minY - 12)
        }
    }
}

/// Corner brackets for focus area
struct FocusCorners: View {
    let rect: CGRect
    let cornerLength: CGFloat = 20
    let lineWidth: CGFloat = 2

    var body: some View {
        let color = Color.yellow.opacity(0.8)

        ZStack {
            // Top-left corner
            Path { path in
                path.move(to: CGPoint(x: rect.minX, y: rect.minY + cornerLength))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.minX + cornerLength, y: rect.minY))
            }
            .stroke(color, lineWidth: lineWidth)

            // Top-right corner
            Path { path in
                path.move(to: CGPoint(x: rect.maxX - cornerLength, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cornerLength))
            }
            .stroke(color, lineWidth: lineWidth)

            // Bottom-left corner
            Path { path in
                path.move(to: CGPoint(x: rect.minX, y: rect.maxY - cornerLength))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX + cornerLength, y: rect.maxY))
            }
            .stroke(color, lineWidth: lineWidth)

            // Bottom-right corner
            Path { path in
                path.move(to: CGPoint(x: rect.maxX - cornerLength, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerLength))
            }
            .stroke(color, lineWidth: lineWidth)
        }
    }
}

// MARK: - Bounding Box View
/// Displays a bounding box around a detected object
struct BoundingBoxView: View {
    let object: DetectedObject
    let containerSize: CGSize

    /// Convert Vision coordinates (bottom-left origin) to SwiftUI (top-left origin)
    private var displayRect: CGRect {
        let box = object.boundingBox
        return CGRect(
            x: box.origin.x * containerSize.width,
            y: (1 - box.origin.y - box.height) * containerSize.height,
            width: box.width * containerSize.width,
            height: box.height * containerSize.height
        )
    }

    private var boxColor: Color {
        object.isInFocusArea ? .green : .blue.opacity(0.6)
    }

    private var lineWidth: CGFloat {
        object.isInFocusArea ? 3 : 2
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Bounding box rectangle
            RoundedRectangle(cornerRadius: 4)
                .stroke(boxColor, lineWidth: lineWidth)
                .frame(width: displayRect.width, height: displayRect.height)

            // Label tag
            HStack(spacing: 4) {
                Text(object.label)
                    .font(.caption2)
                    .fontWeight(.semibold)

                Text(object.confidencePercent)
                    .font(.caption2)
                    .opacity(0.8)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(boxColor)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .offset(y: -24)
        }
        .position(x: displayRect.midX, y: displayRect.midY)
    }
}

// MARK: - Detection Badge
/// Shows count of detected objects
struct DetectionBadge: View {
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "viewfinder")
                .font(.caption)
            Text("\(count)")
                .font(.caption)
                .fontWeight(.bold)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.green.opacity(0.8))
        .clipShape(Capsule())
    }
}

// MARK: - Describe Button
/// Button to trigger voice description of detected objects
struct DescribeButton: View {
    let result: DetectionResult?
    @ObservedObject var voiceFeedback: VoiceFeedbackManager
    let isStreaming: Bool

    private var isEnabled: Bool {
        isStreaming && result != nil
    }

    private var buttonColor: Color {
        if voiceFeedback.isSpeaking {
            return .orange
        }
        if result?.hasFocusedObjects == true {
            return .green
        }
        return .blue
    }

    private var buttonIcon: String {
        if voiceFeedback.isSpeaking {
            return "speaker.wave.3.fill"
        }
        return "speaker.wave.2"
    }

    private var buttonText: String {
        if voiceFeedback.isSpeaking {
            return "Speaking..."
        }
        return "Describe"
    }

    var body: some View {
        Button {
            if voiceFeedback.isSpeaking {
                voiceFeedback.stopSpeaking()
            } else if let result = result {
                voiceFeedback.describe(result)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: buttonIcon)
                    .font(.title2)
                    .symbolEffect(.pulse, isActive: voiceFeedback.isSpeaking)

                Text(buttonText)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(
                Capsule()
                    .fill(buttonColor)
            )
            .shadow(color: buttonColor.opacity(0.5), radius: 8, y: 4)
        }
        .disabled(!isEnabled && !voiceFeedback.isSpeaking)
        .opacity(isEnabled || voiceFeedback.isSpeaking ? 1.0 : 0.5)
        .animation(.easeInOut(duration: 0.2), value: voiceFeedback.isSpeaking)
    }
}

// MARK: - Processing Indicator
/// Shows when object detection is processing
struct ProcessingIndicator: View {
    let isProcessing: Bool

    var body: some View {
        if isProcessing {
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(.white)
                Text("Analyzing...")
                    .font(.caption)
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.6))
            .clipShape(Capsule())
        }
    }
}

// MARK: - Preview
#Preview("Tracking Mode") {
    ZStack {
        Color.black

        DetectionOverlayView(
            result: DetectionResult(
                trackedObjects: [
                    TrackedObject(
                        boundingBox: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4),
                        saliency: 0.92,
                        trackingLabel: "Object 1",
                        colorIndex: 0
                    ),
                    TrackedObject(
                        boundingBox: CGRect(x: 0.1, y: 0.6, width: 0.25, height: 0.2),
                        saliency: 0.78,
                        trackingLabel: "Object 2",
                        colorIndex: 1
                    ),
                    TrackedObject(
                        boundingBox: CGRect(x: 0.7, y: 0.2, width: 0.2, height: 0.3),
                        saliency: 0.65,
                        trackingLabel: "Object 3",
                        colorIndex: 2
                    )
                ],
                timestamp: Date(),
                processingTimeMs: 45
            )
        )
    }
}

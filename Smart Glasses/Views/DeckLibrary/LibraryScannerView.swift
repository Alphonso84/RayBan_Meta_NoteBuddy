//
//  LibraryScannerView.swift
//  Smart Glasses
//
//  Scanner view using Meta Smart Glasses camera
//

import MWDATCamera
import SwiftUI
import SwiftData

/// Standalone scanner view using Smart Glasses camera
struct LibraryScannerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var manager = WearablesManager.shared
    @StateObject private var processor = DocumentReaderProcessor()
    @StateObject private var summarizer = StreamingSummarizer()

    @State private var showingDeckSelector = false
    @State private var pendingCard: SummaryCard?
    @State private var animationPhase: Double = 0
    @State private var isAutoCaptureOn = true  // Auto-capture enabled by default
    @State private var frameSize: CGSize = .zero
    @State private var isMultiPageMode = true  // Multi-page enabled by default
    @State private var showPageCapturedOptions = false  // Show options after page capture

    var body: some View {
        NavigationStack {
            ZStack {
                // Glasses camera preview or connection status
                glassesPreview

                // Document boundary overlay (only show during auto-capture scanning)
                if manager.streamState == .streaming && isAutoCaptureOn && summarizer.state == .idle {
                    DocumentBoundaryOverlay(
                        boundary: processor.detectedBoundary,
                        stabilityProgress: processor.stabilityProgress,
                        isStable: processor.isDocumentStable,
                        statusText: processor.autoCaptureStatus,
                        frameSize: frameSize
                    )
                }

                // Overlay content
                VStack(spacing: 0) {
                    // Top bar with title and auto-capture toggle
                    HStack {
                        // Auto-capture toggle
                        Button {
                            isAutoCaptureOn.toggle()
                            if isAutoCaptureOn {
                                processor.startAutoCapture()
                            } else {
                                processor.stopAutoCapture()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: isAutoCaptureOn ? "a.circle.fill" : "a.circle")
                                    .font(.system(size: 20))
                                Text("Auto")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .foregroundStyle(isAutoCaptureOn ? .green : .white.opacity(0.7))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                        }

                        Spacer()

                        Text("Scan Document")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 2)

                        Spacer()

                        // Page counter badge (when pages captured)
                        if processor.capturedPageCount > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.on.doc.fill")
                                    .font(.system(size: 14))
                                Text("\(processor.capturedPageCount)")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.blue)
                            .clipShape(Capsule())
                        } else {
                            // Placeholder for balance
                            Color.clear
                                .frame(width: 70, height: 32)
                        }
                    }
                    .padding()
                    .background(
                        LinearGradient(
                            colors: [.black.opacity(0.6), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    Spacer()

                    // Status and content area (hide default status when auto-capture is showing overlay)
                    VStack(spacing: 24) {
                        // Status indicator (only show when not in auto-capture scanning mode)
                        if !isAutoCaptureOn || summarizer.state != .idle || processor.state == .complete {
                            statusSection
                        }

                        // Content area (streaming summary)
                        if summarizer.state == .summarizing || summarizer.state == .complete {
                            summaryCard
                        }
                    }
                    .padding()

                    Spacer()

                    // Bottom controls
                    bottomControls
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [.clear, .black.opacity(0.8)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingDeckSelector) {
                if let card = pendingCard {
                    CardPreviewSheet(
                        card: card,
                        onSave: { deck in
                            saveCard(card, to: deck)
                            showingDeckSelector = false
                            pendingCard = nil
                        },
                        onDiscard: {
                            showingDeckSelector = false
                            pendingCard = nil
                            reset()
                        }
                    )
                }
            }
            .onAppear {
                startGlassesStream()
                if isAutoCaptureOn {
                    processor.startAutoCapture()
                }
                if isMultiPageMode {
                    processor.startMultiPageSession()
                }
            }
            .onDisappear {
                stopGlassesStream()
                processor.stopAutoCapture()
            }
            .onChange(of: processor.latestResult) { _, newResult in
                if let result = newResult, !result.extractedText.isEmpty {
                    if isMultiPageMode {
                        // In multi-page mode, show options instead of immediately summarizing
                        showPageCapturedOptions = true
                    } else {
                        // Single page mode - summarize immediately
                        startSummarization(for: result)
                    }
                }
            }
            .onChange(of: processor.state) { _, newState in
                // Reset page captured options when going back to scanning
                if newState == .scanning || newState == .idle {
                    showPageCapturedOptions = false
                }
            }
            .onChange(of: manager.latestFrameImage) { _, newImage in
                // Feed frames to auto-capture processor
                if let image = newImage, isAutoCaptureOn, summarizer.state == .idle {
                    processor.processFrameForAutoCapture(image)
                }
            }
        }
    }

    // MARK: - Glasses Preview

    private var glassesPreview: some View {
        GeometryReader { geometry in
            if manager.streamState == .streaming, let image = manager.latestFrameImage {
                // Live feed from Smart Glasses
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .onAppear {
                        frameSize = geometry.size
                    }
                    .onChange(of: geometry.size) { _, newSize in
                        frameSize = newSize
                    }
            } else {
                // Not connected or no stream
                Color.black
                    .overlay {
                        glassesConnectionStatus
                    }
            }
        }
        .ignoresSafeArea()
    }

    private var glassesConnectionStatus: some View {
        VStack(spacing: 20) {
            // Glasses icon
            Image(systemName: "eyeglasses")
                .font(.system(size: 64))
                .foregroundStyle(.gray)

            // Connection status
            VStack(spacing: 8) {
                Text(connectionStatusTitle)
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(connectionStatusSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            // Action buttons based on state
            if manager.registrationStateDescription != "Registered" {
                Button {
                    manager.startRegistration()
                } label: {
                    Label("Connect Glasses", systemImage: "link")
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            } else if manager.streamState != .streaming {
                Button {
                    startGlassesStream()
                } label: {
                    Label("Start Stream", systemImage: "play.fill")
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.green)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            } else {
                // Streaming but no frame yet
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)
                    Text("Waiting for video...")
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
            }

            // Settings hint
            if manager.registrationStateDescription != "Registered" {
                Text("Go to Settings tab to manage glasses connection")
                    .font(.caption)
                    .foregroundStyle(.gray.opacity(0.7))
                    .padding(.top, 8)
            }
        }
    }

    private var connectionStatusTitle: String {
        switch manager.streamState {
        case .streaming:
            return "Connected"
        case .starting:
            return "Connecting..."
        case .stopping:
            return "Disconnecting..."
        case .stopped:
            if manager.registrationStateDescription == "Registered" {
                return "Glasses Ready"
            } else {
                return "Glasses Not Connected"
            }
        @unknown default:
            return "Unknown State"
        }
    }

    private var connectionStatusSubtitle: String {
        switch manager.streamState {
        case .streaming:
            return "Receiving video from Smart Glasses"
        case .starting:
            return "Establishing connection..."
        case .stopping:
            return "Closing connection..."
        case .stopped:
            if manager.registrationStateDescription == "Registered" {
                return "Tap Start Stream to begin scanning"
            } else {
                return "Connect your Meta Ray-Ban Smart Glasses to scan documents"
            }
        @unknown default:
            return ""
        }
    }

    // MARK: - Status Section

    private var statusSection: some View {
        VStack(spacing: 12) {
            // Animated status icon
            statusIcon
                .frame(width: 60, height: 60)

            // Status text
            Text(statusText)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(.white)

            // Subtitle
            Text(statusSubtitle)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(.ultraThinMaterial.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch summarizer.state {
        case .idle:
            if processor.state == .idle {
                Image(systemName: "viewfinder")
                    .font(.system(size: 28))
                    .foregroundStyle(.white)
            } else {
                ZStack {
                    Circle()
                        .stroke(Color.blue.opacity(0.3), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: 0.3)
                        .stroke(Color.blue, lineWidth: 3)
                        .rotationEffect(.degrees(animationPhase))
                }
                .onAppear {
                    withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                        animationPhase = 360
                    }
                }
            }

        case .preparing:
            ProgressView()
                .scaleEffect(1.2)
                .tint(.white)

        case .summarizing:
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.2))
                Circle()
                    .trim(from: 0, to: summarizer.progress)
                    .stroke(Color.purple, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                Image(systemName: "sparkles")
                    .font(.system(size: 20))
                    .foregroundStyle(.purple)
                    .symbolEffect(.pulse, options: .repeating)
            }

        case .complete:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.green)
                .symbolEffect(.bounce)

        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.orange)
        }
    }

    private var statusText: String {
        // If glasses not connected, show that status
        if manager.streamState != .streaming {
            return "Glasses Not Streaming"
        }

        switch summarizer.state {
        case .idle:
            // Check for page captured state first
            if showPageCapturedOptions {
                return "Page Ready"
            }

            switch processor.state {
            case .idle, .scanning:
                if processor.capturedPageCount > 0 {
                    return "Scan Next Page"
                }
                return isAutoCaptureOn ? "Auto-Capture Active" : "Ready to Scan"
            case .detectingDocument: return "Detecting..."
            case .documentDetected: return "Document Found"
            case .processingDocument: return "Processing"
            case .readingText, .reading: return "Reading Text"
            case .complete: return "Page Captured"
            default: return "Processing..."
            }
        case .preparing: return "Preparing..."
        case .summarizing:
            if processor.capturedPageCount > 1 {
                return "Summarizing \(processor.capturedPageCount) Pages"
            }
            return "Summarizing"
        case .complete: return "Summary Ready"
        case .error: return "Error"
        }
    }

    private var statusSubtitle: String {
        // If glasses not connected, show that status
        if manager.streamState != .streaming {
            return "Connect glasses to start scanning"
        }

        switch summarizer.state {
        case .idle:
            // Check for page captured state first
            if showPageCapturedOptions {
                return "Add page, tap Done to summarize, or Skip"
            }

            switch processor.state {
            case .idle, .scanning:
                if processor.capturedPageCount > 0 {
                    return "Point at next page or tap Done to summarize"
                }
                return isAutoCaptureOn ? "Hold document steady to capture" : "Point at a document and tap capture"
            case .detectingDocument: return "Looking for document edges..."
            case .documentDetected: return "Hold steady..."
            case .processingDocument: return "Adjusting perspective..."
            case .readingText, .reading: return "Extracting text..."
            case .complete: return "Choose an action below"
            default: return "Processing..."
            }
        case .preparing: return "Getting ready..."
        case .summarizing: return "Using on-device AI"
        case .complete: return "Tap Save to keep this card"
        case .error: return summarizer.errorMessage ?? "Try again"
        }
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title
            if !summarizer.suggestedTitle.isEmpty {
                Text(summarizer.suggestedTitle)
                    .font(.headline)
                    .foregroundStyle(.white)
            }

            // Document type badge
            if !summarizer.documentType.isEmpty {
                Text(summarizer.documentType)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.purple.opacity(0.3))
                    .foregroundStyle(.purple)
                    .clipShape(Capsule())
            }

            Divider()
                .background(.white.opacity(0.3))

            // Summary text (streams in)
            if !summarizer.streamingSummary.isEmpty {
                Text(summarizer.streamingSummary)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(4)
            }

            // Key points (stream in)
            if !summarizer.streamingKeyPoints.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(summarizer.streamingKeyPoints.prefix(3), id: \.self) { point in
                        HStack(alignment: .top, spacing: 6) {
                            Circle()
                                .fill(Color.purple)
                                .frame(width: 5, height: 5)
                                .padding(.top, 5)

                            Text(point)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.8))
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.purple.opacity(0.5), lineWidth: 1)
        )
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: 12) {
            // Page info when in multi-page mode with captured pages
            if isMultiPageMode && processor.capturedPageCount > 0 {
                multiPageInfoBar
            }

            HStack(spacing: 16) {
                if summarizer.state == .complete {
                    // Summary complete - show save/discard
                    Button {
                        reset()
                    } label: {
                        Label("Discard", systemImage: "trash")
                            .font(.headline)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    Button {
                        createCardAndShowSelector()
                    } label: {
                        Label("Save Card", systemImage: "square.and.arrow.down")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                } else if showPageCapturedOptions && isMultiPageMode {
                    // Page captured in multi-page mode - show options
                    multiPageCaptureOptions
                } else if isAutoCaptureOn {
                    // Auto-capture mode - show stability or manual capture
                    autoCaptureControls
                } else {
                    // Manual capture mode
                    manualCaptureButton
                }
            }
        }
    }

    // Multi-page info bar showing accumulated pages
    private var multiPageInfoBar: some View {
        HStack(spacing: 12) {
            // Page thumbnails (show up to 4)
            HStack(spacing: -8) {
                ForEach(Array(processor.capturedPageThumbnails.prefix(4).enumerated()), id: \.offset) { index, thumbnail in
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 32, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.white, lineWidth: 1)
                        )
                        .zIndex(Double(4 - index))
                }
                if processor.capturedPageCount > 4 {
                    Text("+\(processor.capturedPageCount - 4)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 40)
                        .background(Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("\(processor.capturedPageCount) \(processor.capturedPageCount == 1 ? "page" : "pages") captured")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)

                Text("\(processor.totalCharacterCount) characters")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // Options shown after capturing a page in multi-page mode
    private var multiPageCaptureOptions: some View {
        HStack(spacing: 12) {
            // Add page and continue
            Button {
                addPageAndContinue()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "plus.rectangle.on.rectangle")
                        .font(.title2)
                    Text("Add Page")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            // Finish and summarize
            Button {
                finishAndSummarize()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                    Text("Done")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            // Cancel current page
            Button {
                cancelCurrentPage()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "xmark.circle")
                        .font(.title2)
                    Text("Skip")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    // Auto-capture controls
    private var autoCaptureControls: some View {
        Group {
            if processor.detectedBoundary != nil {
                HStack(spacing: 12) {
                    StabilityIndicator(
                        progress: processor.stabilityProgress,
                        isStable: processor.isDocumentStable
                    )

                    Text(processor.autoCaptureStatus)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                Button {
                    captureDocument()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "camera.viewfinder")
                            .font(.title2)
                        Text("Manual Capture")
                            .font(.headline)
                    }
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(.ultraThinMaterial)
                            )
                    )
                }
                .disabled(!canCapture)
            }
        }
    }

    // Manual capture button
    private var manualCaptureButton: some View {
        Button {
            captureDocument()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "camera.viewfinder")
                    .font(.title2)
                Text("Capture")
                    .font(.headline)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(canCapture ? Color.blue : Color.gray)
            )
        }
        .disabled(!canCapture)
    }

    private var canCapture: Bool {
        manager.streamState == .streaming &&
        manager.latestFrameImage != nil &&
        (processor.state == .idle || processor.state == .scanning || processor.state == .complete) &&
        !showPageCapturedOptions
    }

    // MARK: - Glasses Stream Control

    private func startGlassesStream() {
        if manager.streamState == .stopped {
            manager.startStream()
        }
    }

    private func stopGlassesStream() {
        // Don't stop stream when leaving - it may be used by other views
        // Stream management is handled by WearablesManager based on app state
    }

    // MARK: - Actions

    private func captureDocument() {
        guard let image = manager.latestFrameImage else { return }
        processor.captureAndProcess(image)
    }

    private func startSummarization(for result: DocumentReadingResult) {
        Task {
            _ = await summarizer.summarize(result.extractedText)
        }
    }

    // MARK: - Multi-Page Actions

    /// Add current page to session and continue scanning
    private func addPageAndContinue() {
        processor.addPageToSession()
        showPageCapturedOptions = false

        // Re-enable auto-capture for next page
        if isAutoCaptureOn {
            processor.startAutoCapture()
        }
    }

    /// Finish multi-page session and start summarization
    private func finishAndSummarize() {
        // Add current page first if not already added
        if processor.latestResult != nil {
            processor.addPageToSession()
        }

        // Get combined text and summarize
        let combinedText = processor.finishMultiPageSession()
        showPageCapturedOptions = false

        // Summarize all pages together
        Task {
            _ = await summarizer.summarize(combinedText)
        }
    }

    /// Skip current page without adding it
    private func cancelCurrentPage() {
        processor.latestResult = nil
        showPageCapturedOptions = false

        // Reset for next capture
        if isAutoCaptureOn {
            processor.resetAutoCapture()
        } else {
            processor.state = .idle
        }
    }

    private func createCardAndShowSelector() {
        // Get source text - either from multi-page session or single capture
        let sourceText: String
        if processor.capturedPageCount > 0 {
            sourceText = processor.accumulatedText
        } else if let result = processor.latestResult {
            sourceText = result.extractedText
        } else {
            return
        }

        // Create thumbnail from first page or latest result
        var thumbnailData: Data?
        let thumbnailImage = processor.capturedPageThumbnails.first ?? processor.latestResult?.correctedImage

        if let image = thumbnailImage {
            let maxSize: CGFloat = 200
            let scale = min(maxSize / image.size.width, maxSize / image.size.height)
            let newSize = CGSize(
                width: image.size.width * scale,
                height: image.size.height * scale
            )

            UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
            image.draw(in: CGRect(origin: .zero, size: newSize))
            let thumbnail = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()

            thumbnailData = thumbnail?.jpegData(compressionQuality: 0.6)
        }

        // Add page count to title if multi-page
        var title = summarizer.suggestedTitle.isEmpty ? "Untitled" : summarizer.suggestedTitle
        if processor.capturedPageCount > 1 {
            title += " (\(processor.capturedPageCount) pages)"
        }

        let card = SummaryCard(
            title: title,
            summary: summarizer.streamingSummary,
            keyPoints: summarizer.streamingKeyPoints,
            sourceText: sourceText,
            thumbnailData: thumbnailData
        )

        pendingCard = card
        showingDeckSelector = true
    }

    private func saveCard(_ card: SummaryCard, to deck: SummaryDeck?) {
        if let deck = deck {
            card.deck = deck
            deck.cards.append(card)
            deck.markAccessed()
        }

        modelContext.insert(card)

        do {
            try modelContext.save()
        } catch {
            print("[LibraryScannerView] Failed to save card: \(error)")
        }

        reset()
    }

    private func reset() {
        summarizer.reset()
        processor.reset()
        animationPhase = 0

        // Re-enable auto-capture if it was on
        if isAutoCaptureOn {
            processor.startAutoCapture()
        }
    }
}

#Preview {
    LibraryScannerView()
        .modelContainer(for: [SummaryCard.self, SummaryDeck.self], inMemory: true)
}

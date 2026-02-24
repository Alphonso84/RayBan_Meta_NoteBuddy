//
//  AppIntents.swift
//  Smart Glasses
//
//  App Intents for Siri Shortcuts integration
//  Document scanning shortcuts
//

import AppIntents
import MWDATCamera
import SwiftUI

// MARK: - Scan Document Intent

/// Intent to scan a document with smart glasses, extract text, and summarize it
struct ScanDocumentIntent: AppIntent {
    static var title: LocalizedStringResource = "Scan Document"
    static var description = IntentDescription("Scans a document using your smart glasses, extracts text, and generates an AI summary.")

    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let manager = WearablesManager.shared
        let processor = manager.documentReaderProcessor

        // Reset any previous state
        processor.reset()

        // Navigate to Scan tab - this triggers MainTabView's stream management
        NavigationState.shared.selectedTab = .scan

        // Give the tab switch a moment to process
        try? await Task.sleep(nanoseconds: 200_000_000)

        // Start streaming if not already streaming (MainTabView should handle this, but ensure it)
        if manager.streamState == .stopped {
            manager.startStream()
        }

        // Wait for stream to become active (up to 5 seconds)
        var attempts = 0
        while manager.streamState != .streaming && attempts < 50 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            attempts += 1
        }

        guard manager.streamState == .streaming else {
            throw ScanError.connectionFailed
        }

        // Wait for a frame to be available
        attempts = 0
        while manager.latestFrameImage == nil && attempts < 20 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            attempts += 1
        }

        guard let frame = manager.latestFrameImage else {
            throw ScanError.noFrame
        }

        // Capture and process the document
        processor.captureAndProcess(frame)

        // Wait for processing to complete (up to 15 seconds)
        attempts = 0
        while processor.state != .complete && processor.state != .idle && attempts < 150 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            attempts += 1
        }

        // Check OCR results
        guard let result = processor.latestResult, result.hasText else {
            if processor.latestResult?.hasDocument == true {
                return .result(value: "", dialog: "Document detected but no text found.")
            } else {
                return .result(value: "", dialog: "No document detected. Point at a document and try again.")
            }
        }

        let extractedText = result.extractedText

        // Summarize the document using AI (respects provider setting)
        let summarizer = StreamingSummarizer()
        await summarizer.checkAvailability()
        // Provider selection is read from @AppStorage automatically

        guard let summaryOutput = await summarizer.summarize(extractedText) else {
            // Fallback to raw text if summarization fails
            let preview = extractedText.count > 200 ? String(extractedText.prefix(200)) + "..." : extractedText
            return .result(value: extractedText, dialog: "Scanned: \(preview)")
        }

        // Build the output string with summary and key points
        var outputText = summaryOutput.summary
        if !summaryOutput.keyPoints.isEmpty {
            outputText += "\n\nKey Points:\n"
            for point in summaryOutput.keyPoints {
                outputText += "• \(point)\n"
            }
        }

        // Create a spoken dialog with the title and summary
        let dialogText = "\(summaryOutput.suggestedTitle): \(summaryOutput.summary)"

        return .result(value: outputText, dialog: "\(dialogText)")
    }
}

/// Errors for scanning intents
enum ScanError: Error, CustomLocalizedStringResourceConvertible {
    case connectionFailed
    case noFrame
    case processingFailed
    case summarizationFailed

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .connectionFailed:
            return "Unable to connect to smart glasses. Make sure they're connected."
        case .noFrame:
            return "Could not get an image. Please try again."
        case .processingFailed:
            return "Failed to process the document."
        case .summarizationFailed:
            return "Failed to summarize the document."
        }
    }
}

// MARK: - App Shortcuts Provider

/// Provides shortcuts that appear in Siri and Shortcuts app
struct SmartGlassesShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ScanDocumentIntent(),
            phrases: [
                "Scan this with \(.applicationName)",
                "Scan document with \(.applicationName)",
                "Scan with \(.applicationName)",
                "\(.applicationName) scan this",
                "\(.applicationName) scan document",
                "Read this with \(.applicationName)",
                "Read document with \(.applicationName)",
                "Capture document with \(.applicationName)",
                "Summarize this with \(.applicationName)",
                "Summarize document with \(.applicationName)"
            ],
            shortTitle: "Scan Document",
            systemImageName: "doc.viewfinder"
        )
    }
}

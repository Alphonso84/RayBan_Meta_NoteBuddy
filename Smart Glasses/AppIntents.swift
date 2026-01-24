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

/// Intent to scan a document with smart glasses
struct ScanDocumentIntent: AppIntent {
    static var title: LocalizedStringResource = "Scan Document"
    static var description = IntentDescription("Scans a document using your smart glasses and extracts text.")

    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let manager = WearablesManager.shared
        let processor = manager.documentReaderProcessor

        // Reset any previous state
        processor.reset()

        // Start streaming if not already streaming
        let wasAlreadyStreaming = manager.streamState == .streaming
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
            if !wasAlreadyStreaming {
                manager.stopStream()
            }
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

        // Stop streaming if we started it
        if !wasAlreadyStreaming {
            manager.stopStream()
        }

        // Check results
        guard let result = processor.latestResult, result.hasText else {
            if processor.latestResult?.hasDocument == true {
                return .result(value: "", dialog: "Document detected but no text found.")
            } else {
                return .result(value: "", dialog: "No document detected. Point at a document and try again.")
            }
        }

        let text = result.extractedText
        let preview = text.count > 200 ? String(text.prefix(200)) + "..." : text

        return .result(value: text, dialog: "Document scanned: \(preview)")
    }
}

/// Errors for scanning intents
enum ScanError: Error, CustomLocalizedStringResourceConvertible {
    case connectionFailed
    case noFrame
    case processingFailed

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .connectionFailed:
            return "Unable to connect to smart glasses. Make sure they're connected."
        case .noFrame:
            return "Could not get an image. Please try again."
        case .processingFailed:
            return "Failed to process the document."
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
                "Scan document with \(.applicationName)",
                "\(.applicationName) scan document",
                "Read document with \(.applicationName)",
                "\(.applicationName) read document",
                "Scan page with \(.applicationName)"
            ],
            shortTitle: "Scan Document",
            systemImageName: "doc.viewfinder"
        )
    }
}

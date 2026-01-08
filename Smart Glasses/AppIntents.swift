//
//  AppIntents.swift
//  Smart Glasses
//
//  App Intents for Siri Shortcuts integration
//  Allows users to start AI Assistant via Siri
//

import AppIntents
import SwiftUI
import MWDATCamera
import UniformTypeIdentifiers

// MARK: - Start AI Assistant Intent

/// Intent to start the AI Assistant mode and begin listening
struct StartAIAssistantIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Smart Glasses AI Assistant"
    static var description = IntentDescription("Starts the AI Assistant on your smart glasses and begins listening for your voice.")

    /// Opens the app when run from Shortcuts
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let manager = WearablesManager.shared
        let assistant = OpenAIVoiceAssistant.shared

        // Check if API key is configured
        guard assistant.hasAPIKey else {
            return .result(dialog: "Please configure your OpenAI API key in the app first.")
        }

        // Set mode to AI Assistant
        manager.currentMode = .aiAssistant

        // Start streaming if not already streaming
        if manager.streamState == .stopped {
            manager.startStream()
            // Give the stream a moment to start
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }

        // Start recording/listening
        assistant.startRecording()

        return .result(dialog: "AI Assistant started. I'm listening.")
    }
}

// MARK: - Take Photo Intent

/// Intent to capture a photo using the smart glasses
struct TakePhotoIntent: AppIntent {
    static var title: LocalizedStringResource = "Take Smart Glasses Photo"
    static var description = IntentDescription("Captures a photo using your Meta Ray-Ban smart glasses and saves it to your camera roll.")

    /// Opens the app when run from Shortcuts
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> & ProvidesDialog {
        let manager = WearablesManager.shared

        // Start streaming if not already streaming
        let wasAlreadyStreaming = manager.streamState == .streaming
        if manager.streamState == .stopped {
            manager.startStream()
        }

        // Wait for stream to become active (up to 5 seconds)
        var attempts = 0
        while manager.streamState != .streaming && attempts < 50 {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            attempts += 1
        }

        // Check if stream is active
        guard manager.streamState == .streaming else {
            throw TakePhotoError.streamFailed
        }

        // Store the current photo to detect when a new one arrives
        let previousPhoto = manager.lastCapturedPhoto

        // Clear previous status and capture the photo
        manager.photoSaveStatus = nil
        manager.capturePhoto()

        // Wait for new photo to be captured (up to 5 seconds)
        attempts = 0
        while manager.lastCapturedPhoto === previousPhoto && attempts < 50 {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            attempts += 1
        }

        // Check if we got a new photo
        guard let capturedPhoto = manager.lastCapturedPhoto,
              capturedPhoto !== previousPhoto else {
            // Stop streaming if we started it
            if !wasAlreadyStreaming {
                manager.stopStream()
            }
            throw TakePhotoError.captureFailed
        }

        // Wait for photo to be saved (up to 5 seconds)
        attempts = 0
        while manager.photoSaveStatus == nil && attempts < 50 {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            attempts += 1
        }

        // Stop streaming if we started it (clean up)
        if !wasAlreadyStreaming {
            manager.stopStream()
        }

        // Convert photo to IntentFile for Shortcuts
        guard let imageData = capturedPhoto.jpegData(compressionQuality: 0.9) else {
            throw TakePhotoError.encodingFailed
        }

        let filename = "SmartGlasses_\(Int(Date().timeIntervalSince1970)).jpg"
        let intentFile = IntentFile(data: imageData, filename: filename, type: .jpeg)

        return .result(value: intentFile, dialog: "Photo captured!")
    }
}

/// Errors for TakePhotoIntent
enum TakePhotoError: Error, CustomLocalizedStringResourceConvertible {
    case streamFailed
    case captureFailed
    case encodingFailed

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .streamFailed:
            return "Unable to connect to smart glasses. Make sure they're connected and try again."
        case .captureFailed:
            return "Failed to capture photo. Please try again."
        case .encodingFailed:
            return "Failed to process the captured photo."
        }
    }
}

// MARK: - Stop AI Assistant Intent

/// Intent to stop the AI Assistant
struct StopAIAssistantIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Smart Glasses AI Assistant"
    static var description = IntentDescription("Stops the AI Assistant and ends the conversation.")

    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let assistant = OpenAIVoiceAssistant.shared

        // Reset the assistant
        assistant.reset()

        return .result(dialog: "AI Assistant stopped.")
    }
}

// MARK: - Send to AI Assistant Intent

/// Intent to send a voice message to the AI Assistant
struct SendToAIAssistantIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask Smart Glasses AI"
    static var description = IntentDescription("Send a question to the AI Assistant on your smart glasses.")

    static var openAppWhenRun: Bool = true

    @Parameter(title: "Question", description: "What would you like to ask?")
    var question: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let manager = WearablesManager.shared
        let assistant = OpenAIVoiceAssistant.shared

        // Check if API key is configured
        guard assistant.hasAPIKey else {
            return .result(dialog: "Please configure your OpenAI API key in the app first.")
        }

        // Set mode to AI Assistant
        manager.currentMode = .aiAssistant

        // Start streaming if not already streaming
        if manager.streamState == .stopped {
            manager.startStream()
            // Give the stream a moment to start
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }

        // Send the text message
        assistant.sendTextMessage(question)

        return .result(dialog: "Sent to AI Assistant: \(question)")
    }
}

// MARK: - Switch Mode Intent

/// Intent to switch streaming modes
struct SwitchModeIntent: AppIntent {
    static var title: LocalizedStringResource = "Switch Smart Glasses Mode"
    static var description = IntentDescription("Switch the processing mode on your smart glasses.")

    static var openAppWhenRun: Bool = true

    @Parameter(title: "Mode", description: "Which mode to switch to")
    var mode: StreamingModeEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let manager = WearablesManager.shared

        manager.currentMode = mode.streamingMode

        return .result(dialog: "Switched to \(mode.streamingMode.rawValue) mode.")
    }
}

// MARK: - Streaming Mode Entity for App Intents

/// App Entity representing streaming modes
struct StreamingModeEntity: AppEntity {
    var id: String
    var streamingMode: StreamingMode

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Streaming Mode"

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(streamingMode.rawValue)")
    }

    static var defaultQuery = StreamingModeQuery()

    init(mode: StreamingMode) {
        self.id = mode.rawValue
        self.streamingMode = mode
    }
}

struct StreamingModeQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [StreamingModeEntity] {
        return identifiers.compactMap { id in
            StreamingMode.allCases.first { $0.rawValue == id }.map { StreamingModeEntity(mode: $0) }
        }
    }

    func suggestedEntities() async throws -> [StreamingModeEntity] {
        return StreamingMode.allCases.map { StreamingModeEntity(mode: $0) }
    }

    func defaultResult() async -> StreamingModeEntity? {
        return StreamingModeEntity(mode: .aiAssistant)
    }
}

// MARK: - App Shortcuts Provider

/// Provides shortcuts that appear in Siri and Shortcuts app
struct SmartGlassesShortcuts: AppShortcutsProvider {

    /// The shortcuts available for this app
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartAIAssistantIntent(),
            phrases: [
                "Start \(.applicationName) AI",
                "Start \(.applicationName) AI Assistant",
                "Start \(.applicationName) assistant",
                "Hey \(.applicationName)",
                "Ask \(.applicationName)",
                "Talk to \(.applicationName)"
            ],
            shortTitle: "Start AI Assistant",
            systemImageName: "sparkles"
        )

        AppShortcut(
            intent: StopAIAssistantIntent(),
            phrases: [
                "Stop \(.applicationName) AI",
                "Stop \(.applicationName) assistant",
                "End \(.applicationName) conversation"
            ],
            shortTitle: "Stop AI Assistant",
            systemImageName: "stop.fill"
        )

        AppShortcut(
            intent: TakePhotoIntent(),
            phrases: [
                "Take a \(.applicationName) photo",
                "Take \(.applicationName) photo",
                "Capture \(.applicationName) photo",
                "Take photo with \(.applicationName)",
                "\(.applicationName) take photo",
                "Snap a \(.applicationName) photo"
            ],
            shortTitle: "Take Photo",
            systemImageName: "camera.fill"
        )

        // Note: SendToAIAssistantIntent is available in Shortcuts app
        // but can't have Siri phrases with String parameters
    }
}

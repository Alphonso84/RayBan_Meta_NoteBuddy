//
//  Smart_GlassesApp.swift
//  Smart Glasses
//
//  Created by Alphonso Sensley II on 12/9/25.
//

import SwiftUI
import AppIntents
import MWDATCore
import MWDATCamera

@main
struct Smart_GlassesApp: App {
    init() {
        configureWearables()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    handleURL(url)
                }
        }
    }

    /// Handle incoming URLs (both Wearables SDK and custom deep links)
    private func handleURL(_ url: URL) {
        // Check for custom deep link schemes
        if url.scheme == "smartglasses" {
            handleCustomDeepLink(url)
            return
        }

        // Handle Wearables SDK URLs
        Task {
            do {
                _ = try await Wearables.shared.handleUrl(url)
            } catch {
                print("Wearables URL handling failed: \(error)")
            }
        }
    }

    /// Handle custom deep links for app actions
    private func handleCustomDeepLink(_ url: URL) {
        guard let host = url.host else { return }

        Task { @MainActor in
            switch host {
            case "start-assistant":
                // Start AI Assistant mode
                let manager = WearablesManager.shared
                let assistant = OpenAIVoiceAssistant.shared

                manager.currentMode = .aiAssistant

                if manager.streamState == .stopped {
                    manager.startStream()
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }

                assistant.startRecording()

            case "stop-assistant":
                // Stop AI Assistant
                OpenAIVoiceAssistant.shared.reset()

            case "mode":
                // Switch mode via URL: smartglasses://mode?name=liveView
                if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let modeName = components.queryItems?.first(where: { $0.name == "name" })?.value,
                   let mode = StreamingMode.allCases.first(where: { $0.rawValue.lowercased().replacingOccurrences(of: " ", with: "") == modeName.lowercased() }) {
                    WearablesManager.shared.currentMode = mode
                }

            default:
                print("Unknown deep link host: \(host)")
            }
        }
    }
}

//
//  Smart_GlassesApp.swift
//  Smart Glasses
//
//  Created by Alphonso Sensley II on 12/9/25.
//

import SwiftUI
import SwiftData
import AppIntents
import MWDATCore
import MWDATCamera

@main
struct Smart_GlassesApp: App {
    let modelContainer: ModelContainer

    init() {
        configureWearables()

        // Initialize SwiftData container
        do {
            let schema = Schema([SummaryCard.self, SummaryDeck.self])
            let modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false
            )
            modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Failed to create SwiftData container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .modelContainer(modelContainer)
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
            case "scan":
                // Start scanning - ensure glasses stream is active
                let manager = WearablesManager.shared
                if manager.streamState == .stopped {
                    manager.startStream()
                }

            case "connect":
                // Initiate glasses connection
                WearablesManager.shared.startRegistration()

            default:
                print("Unknown deep link host: \(host)")
            }
        }
    }
}

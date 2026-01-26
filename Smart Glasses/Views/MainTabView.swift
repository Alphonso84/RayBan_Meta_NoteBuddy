//
//  MainTabView.swift
//  Smart Glasses
//
//  Main tab navigation for the document study app
//

import MWDATCamera
import SwiftUI

/// Tab identifiers
enum AppTab: Int {
    case library = 0
    case scan = 1
    case settings = 2
}

/// Main tab-based navigation
struct MainTabView: View {
    @State private var selectedTab: AppTab = .library
    @ObservedObject private var manager = WearablesManager.shared

    var body: some View {
        TabView(selection: $selectedTab) {
            // Library Tab - Decks and Cards (Landing Page)
            DeckLibraryView()
                .tabItem {
                    Label("Library", systemImage: "books.vertical.fill")
                }
                .tag(AppTab.library)

            // Scan Tab - Document Scanner
            LibraryScannerView()
                .tabItem {
                    Label("Scan", systemImage: "doc.viewfinder")
                }
                .tag(AppTab.scan)

            // Settings Tab - Glasses connection & preferences
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(AppTab.settings)
        }
        .task(id: selectedTab) {
            // This task runs when selectedTab changes and cancels when it changes again
            await handleStreamForTab(selectedTab)
        }
    }

    /// Manage stream based on current tab
    @MainActor
    private func handleStreamForTab(_ tab: AppTab) async {
        if tab == .scan {
            // On Scan tab - start stream if needed
            print("[MainTabView] On Scan tab - ensuring stream is running")
            if manager.streamState == .stopped {
                manager.startStream()
            }

            // Keep this task alive while on Scan tab
            // When tab changes, this task gets cancelled and a new one starts
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            }

            // Task was cancelled = we left the Scan tab
            print("[MainTabView] Left Scan tab - stopping stream")
            manager.stopStream()
        }
        // For other tabs, do nothing (stream stays stopped or was stopped above)
    }
}

#Preview {
    MainTabView()
}

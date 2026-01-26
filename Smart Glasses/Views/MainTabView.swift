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

    var body: some View {
        TabView(selection: $selectedTab) {
            // Library Tab - Decks and Cards (Landing Page)
            DeckLibraryView()
                .tabItem {
                    Label("Library", systemImage: "books.vertical.fill")
                }
                .tag(AppTab.library)

            // Scan Tab - Document Scanner (wrapped for stream lifecycle)
            ScanTabWrapper()
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
    }
}

/// Wrapper view to manage glasses stream lifecycle for the Scan tab
/// Uses onAppear/onDisappear which is more reliable than onChange for TabView
struct ScanTabWrapper: View {
    @ObservedObject private var manager = WearablesManager.shared
    @State private var isVisible = false

    var body: some View {
        LibraryScannerView()
            .onAppear {
                guard !isVisible else { return } // Prevent duplicate calls
                isVisible = true
                print("[ScanTabWrapper] Scan tab appeared - starting stream")
                if manager.streamState == .stopped {
                    manager.startStream()
                }
            }
            .onDisappear {
                guard isVisible else { return } // Prevent duplicate calls
                isVisible = false
                print("[ScanTabWrapper] Scan tab disappeared - stopping stream")
                manager.stopStream()
            }
    }
}

#Preview {
    MainTabView()
}

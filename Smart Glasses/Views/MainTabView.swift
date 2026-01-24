//
//  MainTabView.swift
//  Smart Glasses
//
//  Main tab navigation for the document study app
//

import SwiftUI

/// Main tab-based navigation
struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // Library Tab - Decks and Cards (Landing Page)
            DeckLibraryView()
                .tabItem {
                    Label("Library", systemImage: "books.vertical.fill")
                }
                .tag(0)

            // Scan Tab - Document Scanner
            LibraryScannerView()
                .tabItem {
                    Label("Scan", systemImage: "doc.viewfinder")
                }
                .tag(1)

            // Settings Tab - Glasses connection & preferences
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(2)
        }
    }
}

#Preview {
    MainTabView()
}

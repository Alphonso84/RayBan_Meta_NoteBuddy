//
//  SummaryDeck.swift
//  Smart Glasses
//
//  Created by Claude on 1/22/26.
//

import Foundation
import SwiftData
import SwiftUI

/// A deck containing multiple summary cards for a book/document
@Model
final class SummaryDeck {
    /// Unique identifier
    var id: UUID

    /// Deck title (e.g., "Swift Programming Guide")
    var title: String

    /// Optional description
    var deckDescription: String?

    /// Color theme for the deck (stored as hex string)
    var colorHex: String

    /// Cards in this deck
    @Relationship(deleteRule: .cascade, inverse: \SummaryCard.deck)
    var cards: [SummaryCard]

    /// When the deck was created
    var createdAt: Date

    /// Last time the deck was accessed
    var lastAccessedAt: Date

    /// Whether this is the default "Quick Capture" deck
    var isQuickCapture: Bool

    init(
        id: UUID = UUID(),
        title: String,
        deckDescription: String? = nil,
        colorHex: String = "007AFF",
        cards: [SummaryCard] = [],
        createdAt: Date = Date(),
        lastAccessedAt: Date = Date(),
        isQuickCapture: Bool = false
    ) {
        self.id = id
        self.title = title
        self.deckDescription = deckDescription
        self.colorHex = colorHex
        self.cards = cards
        self.createdAt = createdAt
        self.lastAccessedAt = lastAccessedAt
        self.isQuickCapture = isQuickCapture
    }
}

// MARK: - Convenience Extensions
extension SummaryDeck {
    /// Number of cards in the deck
    var cardCount: Int {
        cards.count
    }

    /// SwiftUI Color from hex string
    var color: Color {
        Color(hex: colorHex) ?? .blue
    }

    /// Formatted last accessed date
    var formattedLastAccessed: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastAccessedAt, relativeTo: Date())
    }

    /// Cards sorted by creation date (newest first)
    var sortedCards: [SummaryCard] {
        cards.sorted { $0.createdAt > $1.createdAt }
    }

    /// Update last accessed timestamp
    func markAccessed() {
        lastAccessedAt = Date()
    }
}

// MARK: - Preset Colors
extension SummaryDeck {
    /// Available deck colors
    static let presetColors: [String] = [
        "007AFF", // Blue
        "34C759", // Green
        "FF9500", // Orange
        "FF2D55", // Pink
        "AF52DE", // Purple
        "5856D6", // Indigo
        "FF3B30", // Red
        "00C7BE", // Teal
        "FFD60A", // Yellow
        "8E8E93"  // Gray
    ]

    /// Get a random preset color
    static var randomColor: String {
        presetColors.randomElement() ?? "007AFF"
    }
}

// MARK: - Color Extension
extension Color {
    /// Initialize Color from hex string
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        guard hexSanitized.count == 6 else { return nil }

        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)

        self.init(
            red: Double((rgb & 0xFF0000) >> 16) / 255.0,
            green: Double((rgb & 0x00FF00) >> 8) / 255.0,
            blue: Double(rgb & 0x0000FF) / 255.0
        )
    }

    /// Convert Color to hex string (approximate)
    var hexString: String {
        // Default to blue if conversion fails
        "007AFF"
    }
}

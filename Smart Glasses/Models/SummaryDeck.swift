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

    // MARK: - Deck Summary Properties

    /// Aggregated summary of all cards in the deck
    var deckSummary: String?

    /// Key themes/points across all cards
    var deckKeyPoints: [String]?

    /// When the deck summary was last generated
    var summaryGeneratedAt: Date?

    // MARK: - Flashcard Properties

    /// Cached flashcards as JSON data
    var flashcardsData: Data?

    /// When flashcards were last generated
    var flashcardsGeneratedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        deckDescription: String? = nil,
        colorHex: String = "007AFF",
        cards: [SummaryCard] = [],
        createdAt: Date = Date(),
        lastAccessedAt: Date = Date(),
        isQuickCapture: Bool = false,
        deckSummary: String? = nil,
        deckKeyPoints: [String]? = nil,
        summaryGeneratedAt: Date? = nil,
        flashcardsData: Data? = nil,
        flashcardsGeneratedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.deckDescription = deckDescription
        self.colorHex = colorHex
        self.cards = cards
        self.createdAt = createdAt
        self.lastAccessedAt = lastAccessedAt
        self.isQuickCapture = isQuickCapture
        self.deckSummary = deckSummary
        self.deckKeyPoints = deckKeyPoints
        self.summaryGeneratedAt = summaryGeneratedAt
        self.flashcardsData = flashcardsData
        self.flashcardsGeneratedAt = flashcardsGeneratedAt
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

    // MARK: - Deck Summary Helpers

    /// Whether the deck has a generated summary
    var hasDeckSummary: Bool {
        deckSummary != nil && !(deckSummary?.isEmpty ?? true)
    }

    /// Whether the summary is potentially outdated (cards added after summary generation)
    var isSummaryOutdated: Bool {
        guard let generatedAt = summaryGeneratedAt else { return true }

        // Check if any card was created after the summary was generated
        return cards.contains { $0.createdAt > generatedAt }
    }

    /// Number of cards added since last summary generation
    var cardsAddedSinceSummary: Int {
        guard let generatedAt = summaryGeneratedAt else { return cards.count }
        return cards.filter { $0.createdAt > generatedAt }.count
    }

    /// Combined source text from all cards (for summarization)
    var combinedSourceText: String {
        sortedCards
            .enumerated()
            .map { index, card in
                "--- Card \(index + 1): \(card.title) ---\n\(card.sourceText)"
            }
            .joined(separator: "\n\n")
    }

    /// Combined summaries from all cards (lighter weight for re-summarization)
    var combinedCardSummaries: String {
        sortedCards
            .enumerated()
            .map { index, card in
                "Card \(index + 1) - \(card.title):\n\(card.summary)\nKey Points: \(card.keyPoints.joined(separator: "; "))"
            }
            .joined(separator: "\n\n")
    }

    /// Total character count of all source text
    var totalSourceTextLength: Int {
        cards.reduce(0) { $0 + $1.sourceText.count }
    }

    /// Clear the deck summary
    func clearDeckSummary() {
        deckSummary = nil
        deckKeyPoints = nil
        summaryGeneratedAt = nil
    }

    // MARK: - Flashcard Helpers

    /// Whether the deck has cached flashcards
    var hasFlashcards: Bool {
        flashcardsData != nil && !(flashcardsData?.isEmpty ?? true)
    }

    /// Whether flashcards are outdated (cards added after generation)
    var areFlashcardsOutdated: Bool {
        guard let generatedAt = flashcardsGeneratedAt else { return true }
        return cards.contains { $0.createdAt > generatedAt }
    }

    /// Number of cards added since flashcards were generated
    var cardsAddedSinceFlashcards: Int {
        guard let generatedAt = flashcardsGeneratedAt else { return cards.count }
        return cards.filter { $0.createdAt > generatedAt }.count
    }

    /// Get cached flashcards
    var cachedFlashcards: [Flashcard]? {
        guard let data = flashcardsData else { return nil }
        return try? JSONDecoder().decode([Flashcard].self, from: data)
    }

    /// Save flashcards to cache
    func saveFlashcards(_ flashcards: [Flashcard]) {
        flashcardsData = try? JSONEncoder().encode(flashcards)
        flashcardsGeneratedAt = Date()
    }

    /// Clear cached flashcards
    func clearFlashcards() {
        flashcardsData = nil
        flashcardsGeneratedAt = nil
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

//
//  LLMProvider.swift
//  Smart Glasses
//
//  Protocol defining the interface for LLM summarization providers
//

import Foundation

/// Protocol that all LLM providers must conform to
protocol LLMProvider {
    /// Human-readable provider name
    var name: String { get }

    /// Whether this provider is currently available and configured
    var isAvailable: Bool { get async }

    /// Summarize document text, optionally streaming partial results
    func summarize(_ text: String, streaming: ((String) -> Void)?) async throws -> DocumentSummaryOutput

    /// Summarize an entire deck of cards, optionally streaming partial results
    func summarizeDeck(cardSummaries: String, cardCount: Int, deckTitle: String, streaming: ((String) -> Void)?) async throws -> DeckSummaryOutput

    /// Generate multiple-choice quiz questions from study material
    func generateQuestions(from text: String, cardTitles: [String], count: Int) async throws -> [QuizQuestion]
}

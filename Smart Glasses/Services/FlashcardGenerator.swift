//
//  FlashcardGenerator.swift
//  Smart Glasses
//
//  Generates flashcards from deck cards using the configured LLM provider
//

import Combine
import Foundation
import SwiftUI

#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
class FlashcardGenerator: ObservableObject {

    // MARK: - State

    enum GeneratorState: Equatable {
        case idle
        case generating
        case complete
        case error(String)
    }

    @Published var state: GeneratorState = .idle
    @Published var flashcards: [Flashcard] = []
    @Published var progress: Double = 0

    @AppStorage("selectedProvider") private var selectedProvider = "apple"

    private lazy var openAIProvider = OpenAIProvider()

    // MARK: - Public

    func generateFlashcards(from cards: [SummaryCard], count: Int = 15) async {
        guard !cards.isEmpty else {
            state = .error("No cards to generate flashcards from")
            return
        }

        state = .generating
        flashcards = []
        progress = 0.1

        // Build combined text from all cards
        let combinedText = cards.map { card in
            """
            Card: \(card.title)
            Summary: \(card.summary)
            Key Points: \(card.keyPoints.joined(separator: "; "))
            """
        }.joined(separator: "\n\n")

        let cardTitles = cards.map(\.title)
        let flashcardCount = min(count, cards.count * 5) // Up to 5 flashcards per card

        progress = 0.2

        // Route to provider
        if selectedProvider == "openai", await openAIProvider.isAvailable {
            await generateWithOpenAI(text: combinedText, cardTitles: cardTitles, count: flashcardCount)
        } else {
            await generateWithAppleIntelligence(text: combinedText, cardTitles: cardTitles, count: flashcardCount)
        }
    }

    func reset() {
        state = .idle
        flashcards = []
        progress = 0
    }

    // MARK: - OpenAI

    private func generateWithOpenAI(text: String, cardTitles: [String], count: Int) async {
        do {
            progress = 0.4
            let generated = try await openAIProvider.generateFlashcards(from: text, cardTitles: cardTitles, count: count)
            progress = 0.9

            if generated.isEmpty {
                flashcards = generateFallbackFlashcards(cardTitles: cardTitles, text: text, count: count)
            } else {
                flashcards = generated
            }

            progress = 1.0
            state = .complete
        } catch {
            print("[FlashcardGenerator] OpenAI error: \(error)")
            flashcards = generateFallbackFlashcards(cardTitles: cardTitles, text: text, count: count)
            progress = 1.0
            state = flashcards.isEmpty ? .error(error.localizedDescription) : .complete
        }
    }

    // MARK: - Apple Intelligence

    private func generateWithAppleIntelligence(text: String, cardTitles: [String], count: Int) async {
        #if canImport(FoundationModels)
        let availability = SystemLanguageModel.default.availability
        guard case .available = availability else {
            flashcards = generateFallbackFlashcards(cardTitles: cardTitles, text: text, count: count)
            progress = 1.0
            state = flashcards.isEmpty ? .error("Apple Intelligence not available") : .complete
            return
        }

        let session = LanguageModelSession(instructions: """
            You are a flashcard generator for study material. Generate flashcards with a term/question on the front and answer/explanation on the back.
            Each flashcard should test one concept clearly.
            Respond with ONLY a JSON array, no other text:
            [{"front": "Question or term", "back": "Answer or explanation", "sourceCard": "card title", "category": "optional category"}]
            """)

        let prompt = """
        Generate \(count) flashcards from this study material.
        Card titles: \(cardTitles.joined(separator: ", "))

        Study material:
        ---
        \(text)
        ---

        Create flashcards that:
        - Have clear, concise questions or terms on the front
        - Have complete but brief answers on the back
        - Cover the most important concepts from the material
        - Vary between definition, concept, and application questions
        """

        do {
            progress = 0.4
            let response = try await session.respond(to: prompt)
            progress = 0.8

            let parsed = parseFlashcardJSON(response.content, fallbackTitles: cardTitles)

            if parsed.isEmpty {
                flashcards = generateFallbackFlashcards(cardTitles: cardTitles, text: text, count: count)
            } else {
                flashcards = parsed
            }

            progress = 1.0
            state = .complete
        } catch {
            print("[FlashcardGenerator] Apple Intelligence error: \(error)")
            flashcards = generateFallbackFlashcards(cardTitles: cardTitles, text: text, count: count)
            progress = 1.0
            state = flashcards.isEmpty ? .error(error.localizedDescription) : .complete
        }
        #else
        flashcards = generateFallbackFlashcards(cardTitles: cardTitles, text: text, count: count)
        progress = 1.0
        state = flashcards.isEmpty ? .error("Foundation Models requires iOS 26+") : .complete
        #endif
    }

    // MARK: - JSON Parsing

    private func parseFlashcardJSON(_ content: String, fallbackTitles: [String]) -> [Flashcard] {
        var jsonString = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if let startRange = jsonString.range(of: "["),
           let endRange = jsonString.range(of: "]", options: .backwards) {
            jsonString = String(jsonString[startRange.lowerBound..<endRange.upperBound])
        }

        guard let data = jsonString.data(using: .utf8) else { return [] }

        struct RawFlashcard: Decodable {
            let front: String
            let back: String
            let sourceCard: String?
            let category: String?
        }

        do {
            let rawFlashcards = try JSONDecoder().decode([RawFlashcard].self, from: data)
            return rawFlashcards.map { raw in
                Flashcard(
                    front: raw.front,
                    back: raw.back,
                    sourceCardTitle: raw.sourceCard ?? fallbackTitles.first ?? "Unknown",
                    category: raw.category
                )
            }
        } catch {
            print("[FlashcardGenerator] JSON parse error: \(error)")
            return []
        }
    }

    // MARK: - Fallback

    private func generateFallbackFlashcards(cardTitles: [String], text: String, count: Int) -> [Flashcard] {
        // Extract key points from the text to build basic flashcards
        let lines = text.components(separatedBy: "\n")
        var flashcards: [Flashcard] = []

        var currentTitle = cardTitles.first ?? "Study Material"
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Card: ") {
                currentTitle = String(trimmed.dropFirst(6))
            } else if trimmed.hasPrefix("Key Points: ") {
                let points = String(trimmed.dropFirst(12)).components(separatedBy: "; ")
                for point in points where !point.isEmpty && flashcards.count < count {
                    flashcards.append(Flashcard(
                        front: "What is a key point about \(currentTitle)?",
                        back: point,
                        sourceCardTitle: currentTitle
                    ))
                }
            }
        }

        return flashcards
    }
}

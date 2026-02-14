//
//  StreamingSummarizer.swift
//  Smart Glasses
//
//  Created by Claude on 1/22/26.
//

import Foundation
import Combine

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Structured summary output for documents
struct DocumentSummaryOutput: Codable, Sendable {
    /// A concise 1-3 sentence summary
    var summary: String

    /// 3-5 key points as bullet points
    var keyPoints: [String]

    /// Auto-generated title for the card
    var suggestedTitle: String

    /// Document type classification
    var documentType: String
}

/// Structured summary output for deck aggregation
struct DeckSummaryOutput: Codable, Sendable {
    /// Comprehensive summary of the entire deck
    var summary: String

    /// Key themes/points across all cards
    var keyThemes: [String]

    /// Number of cards summarized
    var cardCount: Int
}

/// Streaming summarizer using Apple Foundation Models
@MainActor
class StreamingSummarizer: ObservableObject {

    // MARK: - Published Properties

    /// Whether Foundation Models are available
    @Published var isAvailable: Bool = false

    /// Current streaming state
    @Published var state: SummarizerState = .idle

    /// Streaming summary text (updates as tokens arrive)
    @Published var streamingSummary: String = ""

    /// Streaming key points (updates as tokens arrive)
    @Published var streamingKeyPoints: [String] = []

    /// Suggested title from the model
    @Published var suggestedTitle: String = ""

    /// Document type classification
    @Published var documentType: String = ""

    /// Error message if any
    @Published var errorMessage: String?

    /// Progress (0-1) for visual feedback
    @Published var progress: Double = 0

    // MARK: - Private Properties

    #if canImport(FoundationModels)
    private var session: LanguageModelSession?
    #endif

    private var currentTask: Task<Void, Never>?

    // MARK: - State Enum

    enum SummarizerState: Equatable {
        case idle
        case preparing
        case summarizing
        case complete
        case error
    }

    // MARK: - Initialization

    init() {
        Task {
            await checkAvailability()
        }
    }

    // MARK: - Public Methods

    /// Check if Foundation Models are available
    func checkAvailability() async {
        #if canImport(FoundationModels)
        let availability = SystemLanguageModel.default.availability

        switch availability {
        case .available:
            isAvailable = true
            // Create session with instructions for document summarization
            session = LanguageModelSession(instructions: """
                You are a note taking assistant. Your job is to:
                1. Create a concise 1-3 sentence summary of the document text as if you were a college student
                2. Extract 3-5 key points as brief bullet points that would serve as good notes for learning the topic
                3. Suggest a short, descriptive title for this content based on the key points
                4. Classify the document type (e.g., article, letter, receipt, manual, book page, notes)

                Be concise and focus on the most important information.
                Use clear, simple language suitable for text-to-speech.
                """)
            print("[StreamingSummarizer] Foundation Models available")

        case .unavailable(let reason):
            isAvailable = false
            switch reason {
            case .deviceNotEligible:
                errorMessage = "Device does not support Apple Intelligence"
            case .appleIntelligenceNotEnabled:
                errorMessage = "Enable Apple Intelligence in Settings"
            case .modelNotReady:
                errorMessage = "Model downloading, try again later"
            @unknown default:
                errorMessage = "Foundation Models unavailable"
            }
            print("[StreamingSummarizer] Unavailable: \(errorMessage ?? "unknown")")

        @unknown default:
            isAvailable = false
        }
        #else
        isAvailable = false
        errorMessage = "Foundation Models requires iOS 26+"
        #endif
    }

    /// Summarize document text with streaming output
    /// - Parameter text: The OCR text to summarize
    /// - Returns: The final DocumentSummaryOutput
    func summarize(_ text: String) async -> DocumentSummaryOutput? {
        // Cancel any existing task
        currentTask?.cancel()

        // Reset state
        streamingSummary = ""
        streamingKeyPoints = []
        suggestedTitle = ""
        documentType = ""
        progress = 0
        errorMessage = nil
        state = .preparing

        #if canImport(FoundationModels)
        guard isAvailable, let session = session else {
            state = .error
            errorMessage = "Foundation Models not available"
            return await createFallbackSummaryWithStreaming(from: text)
        }

        state = .summarizing

        let prompt = """
        Summarize the following document text:

        ---
        \(text)
        ---

        Provide:
        1. A concise summary as if taking notes in college (1-3 sentences)
        2. Key points that would be useful to learning the topic (3-5 bullet points)
        3. A suggested title
        4. The document type
        """

        do {
            // Use streaming for real-time updates
            var fullResponse = ""
            let stream = session.streamResponse(to: prompt)

            for try await partialResponse in stream {
                fullResponse = partialResponse.content
                progress = min(0.9, progress + 0.05)

                // Parse partial response and update UI in real-time
                let partialOutput = parseResponse(fullResponse, originalText: text)
                streamingSummary = partialOutput.summary
                streamingKeyPoints = partialOutput.keyPoints
                // Only update title if we have a valid non-empty title
                if !partialOutput.suggestedTitle.isEmpty {
                    suggestedTitle = partialOutput.suggestedTitle
                }
                if !partialOutput.documentType.isEmpty && partialOutput.documentType != "Document" {
                    documentType = partialOutput.documentType
                } else if documentType.isEmpty {
                    documentType = partialOutput.documentType
                }
            }

            // Final parse
            let output = parseResponse(fullResponse, originalText: text)
            streamingSummary = output.summary
            streamingKeyPoints = output.keyPoints
            suggestedTitle = output.suggestedTitle
            documentType = output.documentType
            progress = 1.0
            state = .complete

            return output

        } catch {
            print("[StreamingSummarizer] Error: \(error)")
            state = .error
            errorMessage = error.localizedDescription
            return await createFallbackSummaryWithStreaming(from: text)
        }
        #else
        // Fallback for non-iOS 26 devices - use typewriter effect
        return await createFallbackSummaryWithStreaming(from: text)
        #endif
    }

    /// Create fallback summary with typewriter streaming effect
    private func createFallbackSummaryWithStreaming(from text: String) async -> DocumentSummaryOutput {
        state = .summarizing

        let output = createFallbackSummary(from: text)

        // Stream the title first
        await streamText(output.suggestedTitle) { partial in
            self.suggestedTitle = partial
        }

        // Stream document type
        documentType = output.documentType
        progress = 0.2

        // Stream the summary with typewriter effect
        await streamText(output.summary) { partial in
            self.streamingSummary = partial
            self.progress = 0.2 + (Double(partial.count) / Double(output.summary.count)) * 0.5
        }

        // Stream key points one by one
        for (index, point) in output.keyPoints.enumerated() {
            var currentPoints = streamingKeyPoints
            currentPoints.append("")
            streamingKeyPoints = currentPoints

            await streamText(point) { partial in
                var points = self.streamingKeyPoints
                points[index] = partial
                self.streamingKeyPoints = points
            }

            progress = 0.7 + (Double(index + 1) / Double(output.keyPoints.count)) * 0.3
        }

        progress = 1.0
        state = .complete

        return output
    }

    /// Stream text with typewriter effect
    private func streamText(_ text: String, update: @escaping (String) -> Void) async {
        var current = ""
        let words = text.split(separator: " ")

        for word in words {
            current += (current.isEmpty ? "" : " ") + word
            update(current)
            // Small delay between words for typing effect
            try? await Task.sleep(nanoseconds: 30_000_000) // 30ms per word
        }
    }

    /// Summarize an entire deck by aggregating card content
    /// - Parameters:
    ///   - cardSummaries: Combined summaries from all cards
    ///   - cardCount: Number of cards in the deck
    ///   - deckTitle: Title of the deck for context
    /// - Returns: The DeckSummaryOutput with aggregated summary
    func summarizeDeck(cardSummaries: String, cardCount: Int, deckTitle: String) async -> DeckSummaryOutput? {
        // Cancel any existing task
        currentTask?.cancel()

        // Reset state
        streamingSummary = ""
        streamingKeyPoints = []
        progress = 0
        errorMessage = nil
        state = .preparing

        #if canImport(FoundationModels)
        guard isAvailable, let session = session else {
            state = .error
            errorMessage = "Foundation Models not available"
            return await createFallbackDeckSummary(from: cardSummaries, cardCount: cardCount)
        }

        state = .summarizing

        let prompt = """
        You are summarizing a study deck titled "\(deckTitle)" containing \(cardCount) cards.

        Here are the summaries from each card:

        ---
        \(cardSummaries)
        ---

        Create a comprehensive deck summary that:
        1. Provides a cohesive overview (3-5 sentences) that synthesizes the main content across all cards
        2. Identifies 4-6 key themes or important points that span multiple cards
        3. Highlights connections between different cards when relevant

        Focus on creating a unified summary that helps the reader understand the complete content.
        Use clear language suitable for text-to-speech.
        """

        do {
            var fullResponse = ""
            let stream = session.streamResponse(to: prompt)

            for try await partialResponse in stream {
                fullResponse = partialResponse.content
                progress = min(0.9, progress + 0.03)

                // Parse partial response and update UI
                let partialOutput = parseDeckResponse(fullResponse, cardCount: cardCount)
                streamingSummary = partialOutput.summary
                streamingKeyPoints = partialOutput.keyThemes
            }

            // Final parse
            let output = parseDeckResponse(fullResponse, cardCount: cardCount)
            streamingSummary = output.summary
            streamingKeyPoints = output.keyThemes
            progress = 1.0
            state = .complete

            return output

        } catch {
            print("[StreamingSummarizer] Deck summary error: \(error)")
            state = .error
            errorMessage = error.localizedDescription
            return await createFallbackDeckSummary(from: cardSummaries, cardCount: cardCount)
        }
        #else
        return await createFallbackDeckSummary(from: cardSummaries, cardCount: cardCount)
        #endif
    }

    #if canImport(FoundationModels)
    /// Parse deck summary response
    private func parseDeckResponse(_ content: String, cardCount: Int) -> DeckSummaryOutput {
        let lines = content.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }

        var summary = ""
        var keyThemes: [String] = []
        var currentSection = ""

        for line in lines {
            let cleanedLine = stripMarkdownFormatting(line)
            if cleanedLine.isEmpty { continue }

            let lowercased = cleanedLine.lowercased()

            if lowercased.contains("overview:") || lowercased.contains("summary:") ||
               (lowercased.contains("overview") && cleanedLine.contains(":")) {
                currentSection = "summary"
                let parts = cleanedLine.components(separatedBy: ":")
                if parts.count > 1 {
                    summary = stripMarkdownFormatting(parts.dropFirst().joined(separator: ":"))
                }
            } else if lowercased.contains("theme") || lowercased.contains("key point") {
                currentSection = "themes"
            } else if line.hasPrefix("-") || line.hasPrefix("•") || (line.hasPrefix("*") && !line.hasPrefix("**")) {
                let theme = stripMarkdownFormatting(String(line.dropFirst()))
                if !theme.isEmpty && theme != "*" {
                    keyThemes.append(theme)
                }
            } else if currentSection == "summary" && !cleanedLine.isEmpty {
                if summary.isEmpty {
                    summary = cleanedLine
                } else {
                    summary += " " + cleanedLine
                }
            }
        }

        // Fallback if parsing failed
        if summary.isEmpty {
            summary = "This deck contains \(cardCount) cards with study material."
        }

        return DeckSummaryOutput(
            summary: stripMarkdownFormatting(summary),
            keyThemes: keyThemes.map { stripMarkdownFormatting($0) },
            cardCount: cardCount
        )
    }
    #endif

    /// Create fallback deck summary
    private func createFallbackDeckSummary(from cardSummaries: String, cardCount: Int) async -> DeckSummaryOutput {
        state = .summarizing

        // Extract first few sentences as summary
        let sentences = cardSummaries.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count > 20 }

        let summary = sentences.prefix(3).joined(separator: ". ") + "."

        // Extract key points from different cards
        let themes = sentences.prefix(5).map { sentence in
            if sentence.count > 100 {
                return String(sentence.prefix(100)) + "..."
            }
            return sentence
        }

        // Stream with typewriter effect
        await streamText(summary) { partial in
            self.streamingSummary = partial
            self.progress = Double(partial.count) / Double(summary.count) * 0.7
        }

        for (index, theme) in themes.enumerated() {
            var currentThemes = streamingKeyPoints
            currentThemes.append("")
            streamingKeyPoints = currentThemes

            await streamText(theme) { partial in
                var points = self.streamingKeyPoints
                points[index] = partial
                self.streamingKeyPoints = points
            }
            progress = 0.7 + (Double(index + 1) / Double(themes.count)) * 0.3
        }

        progress = 1.0
        state = .complete

        return DeckSummaryOutput(
            summary: summary,
            keyThemes: Array(themes),
            cardCount: cardCount
        )
    }

    /// Cancel current summarization
    func cancel() {
        currentTask?.cancel()
        state = .idle
        progress = 0
    }

    /// Reset the summarizer state
    func reset() {
        cancel()
        streamingSummary = ""
        streamingKeyPoints = []
        suggestedTitle = ""
        documentType = ""
        errorMessage = nil
    }

    // MARK: - Private Methods

    #if canImport(FoundationModels)
    /// Parse the model response into structured output
    private func parseResponse(_ content: String, originalText: String) -> DocumentSummaryOutput {
        // Simple parsing - in production you'd use structured generation
        let lines = content.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }

        var summary = ""
        var keyPoints: [String] = []
        var title = ""
        var docType = "Document"

        var currentSection = ""

        for line in lines {
            // Skip empty lines or lines that are just markdown formatting
            let cleanedLine = stripMarkdownFormatting(line)
            if cleanedLine.isEmpty {
                continue
            }

            let lowercased = cleanedLine.lowercased()

            if lowercased.contains("summary:") || (lowercased.contains("summary") && cleanedLine.contains(":")) {
                currentSection = "summary"
                let parts = cleanedLine.components(separatedBy: ":")
                if parts.count > 1 {
                    summary = stripMarkdownFormatting(parts.dropFirst().joined(separator: ":"))
                }
            } else if lowercased.contains("key point") || lowercased.contains("bullet") {
                currentSection = "keypoints"
            } else if lowercased.contains("title:") || lowercased.contains("suggested title") {
                currentSection = "title"
                let parts = cleanedLine.components(separatedBy: ":")
                if parts.count > 1 {
                    let rawTitle = parts.dropFirst().joined(separator: ":")
                    title = stripMarkdownFormatting(rawTitle)
                }
            } else if lowercased.contains("type:") || lowercased.contains("document type") {
                currentSection = "type"
                let parts = cleanedLine.components(separatedBy: ":")
                if parts.count > 1 {
                    docType = stripMarkdownFormatting(parts.dropFirst().joined(separator: ":"))
                }
            } else if line.hasPrefix("-") || line.hasPrefix("•") || (line.hasPrefix("*") && !line.hasPrefix("**")) {
                // Bullet point - but not markdown bold
                let point = stripMarkdownFormatting(String(line.dropFirst()))
                if !point.isEmpty && point != "*" {
                    keyPoints.append(point)
                }
            } else if line.hasPrefix("**") && line.hasSuffix("**") {
                // This is just a markdown header/bold text, skip it
                continue
            } else if currentSection == "summary" && !cleanedLine.isEmpty && summary.isEmpty {
                summary = cleanedLine
            } else if currentSection == "summary" && !cleanedLine.isEmpty {
                summary += " " + cleanedLine
            } else if currentSection == "title" && title.isEmpty && !cleanedLine.isEmpty {
                title = cleanedLine
            }
        }

        // Fallbacks if parsing failed
        if summary.isEmpty {
            summary = createSimpleSummary(from: originalText)
        }
        if title.isEmpty {
            title = createTitle(from: originalText)
        }
        if keyPoints.isEmpty {
            keyPoints = extractKeyPoints(from: originalText)
        }

        // Clean up any remaining markdown in final output
        summary = stripMarkdownFormatting(summary)
        title = stripMarkdownFormatting(title)
        docType = stripMarkdownFormatting(docType)
        keyPoints = keyPoints.map { stripMarkdownFormatting($0) }

        return DocumentSummaryOutput(
            summary: summary,
            keyPoints: keyPoints,
            suggestedTitle: title,
            documentType: docType
        )
    }

    /// Strip markdown formatting characters from text
    private func stripMarkdownFormatting(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespaces)

        // Remove bold/italic markers
        result = result.replacingOccurrences(of: "**", with: "")
        result = result.replacingOccurrences(of: "__", with: "")
        result = result.replacingOccurrences(of: "~~", with: "")

        // Remove single asterisks/underscores at start and end (italic)
        if result.hasPrefix("*") && result.hasSuffix("*") && result.count > 2 {
            result = String(result.dropFirst().dropLast())
        }
        if result.hasPrefix("_") && result.hasSuffix("_") && result.count > 2 {
            result = String(result.dropFirst().dropLast())
        }

        // Remove markdown headers
        while result.hasPrefix("#") {
            result = String(result.dropFirst())
        }

        return result.trimmingCharacters(in: .whitespaces)
    }
    #endif

    /// Create a fallback summary when Foundation Models unavailable
    private func createFallbackSummary(from text: String) -> DocumentSummaryOutput {
        DocumentSummaryOutput(
            summary: createSimpleSummary(from: text),
            keyPoints: extractKeyPoints(from: text),
            suggestedTitle: createTitle(from: text),
            documentType: "Document"
        )
    }

    /// Create a simple summary by extracting first sentences
    private func createSimpleSummary(from text: String) -> String {
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let firstSentences = sentences.prefix(2).joined(separator: ". ")
        if firstSentences.count > 200 {
            return String(firstSentences.prefix(200)) + "..."
        }
        return firstSentences + (firstSentences.isEmpty ? "" : ".")
    }

    /// Extract key points from text
    private func extractKeyPoints(from text: String) -> [String] {
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count > 20 }

        return Array(sentences.prefix(4)).map { sentence in
            if sentence.count > 80 {
                return String(sentence.prefix(80)) + "..."
            }
            return sentence
        }
    }

    /// Create a title from the text
    private func createTitle(from text: String) -> String {
        let words = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        let titleWords = words.prefix(5).joined(separator: " ")
        if titleWords.count > 40 {
            return String(titleWords.prefix(40)) + "..."
        }
        return titleWords.isEmpty ? "Untitled" : titleWords
    }
}

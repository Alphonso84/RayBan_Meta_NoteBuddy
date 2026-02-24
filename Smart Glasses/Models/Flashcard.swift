//
//  Flashcard.swift
//  Smart Glasses
//
//  In-memory flashcard data structures for study mode
//

import Foundation

/// A single flashcard with front (question/term) and back (answer/explanation)
struct Flashcard: Identifiable {
    let id: UUID
    let front: String           // Term or question
    let back: String            // Answer or explanation
    let sourceCardTitle: String // Which SummaryCard it came from
    let category: String?       // Optional category for grouping
    
    init(
        id: UUID = UUID(),
        front: String,
        back: String,
        sourceCardTitle: String,
        category: String? = nil
    ) {
        self.id = id
        self.front = front
        self.back = back
        self.sourceCardTitle = sourceCardTitle
        self.category = category
    }
}

/// Results from a flashcard study session
struct FlashcardStudyResult {
    let flashcards: [Flashcard]
    let cardsStudied: Int
    let cardsFlipped: Int       // How many times user flipped cards
    let startedAt: Date
    let completedAt: Date
    
    var studyDuration: TimeInterval {
        completedAt.timeIntervalSince(startedAt)
    }
    
    var formattedDuration: String {
        let minutes = Int(studyDuration) / 60
        let seconds = Int(studyDuration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

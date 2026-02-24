//
//  FlashcardStudyResultsView.swift
//  Smart Glasses
//
//  Displays flashcard study session results
//

import SwiftUI

struct FlashcardStudyResultsView: View {
    let result: FlashcardStudyResult
    let deckColor: Color
    let onStudyAgain: () -> Void
    let onDone: () -> Void
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Completion icon
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(deckColor)
                    .padding(.top, 20)
                
                // Stats
                VStack(spacing: 8) {
                    Text("Study Complete!")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("You reviewed \(result.cardsStudied) flashcards")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                // Detailed stats
                HStack(spacing: 32) {
                    statItem(
                        icon: "rectangle.on.rectangle",
                        value: "\(result.flashcards.count)",
                        label: "Total Cards"
                    )
                    
                    statItem(
                        icon: "arrow.triangle.2.circlepath",
                        value: "\(result.cardsFlipped)",
                        label: "Flips"
                    )
                    
                    statItem(
                        icon: "clock",
                        value: result.formattedDuration,
                        label: "Duration"
                    )
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
                
                // Action buttons
                VStack(spacing: 12) {
                    Button {
                        onStudyAgain()
                    } label: {
                        Label("Study Again", systemImage: "arrow.clockwise")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(deckColor)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    
                    Button {
                        onDone()
                    } label: {
                        Text("Done")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.secondarySystemGroupedBackground))
                            .foregroundStyle(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.top, 8)
            }
            .padding()
        }
    }
    
    private func statItem(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(deckColor)
            
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    FlashcardStudyResultsView(
        result: FlashcardStudyResult(
            flashcards: [
                Flashcard(front: "Q1", back: "A1", sourceCardTitle: "Card 1"),
                Flashcard(front: "Q2", back: "A2", sourceCardTitle: "Card 2"),
                Flashcard(front: "Q3", back: "A3", sourceCardTitle: "Card 3")
            ],
            cardsStudied: 3,
            cardsFlipped: 5,
            startedAt: Date().addingTimeInterval(-180),
            completedAt: Date()
        ),
        deckColor: .blue,
        onStudyAgain: {},
        onDone: {}
    )
}

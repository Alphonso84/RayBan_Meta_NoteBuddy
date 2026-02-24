//
//  FlashcardCardView.swift
//  Smart Glasses
//
//  Individual flashcard with realistic 3D flip animation
//

import SwiftUI

struct FlashcardCardView: View {
    let flashcard: Flashcard
    let isFlipped: Bool
    let deckColor: Color
    let onFlip: () -> Void
    
    var body: some View {
        ZStack {
            // Back of card (answer)
            cardBack
                .rotation3DEffect(
                    .degrees(isFlipped ? 0 : 180),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.5
                )
                .opacity(isFlipped ? 1 : 0)
            
            // Front of card (question)
            cardFront
                .rotation3DEffect(
                    .degrees(isFlipped ? -180 : 0),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.5
                )
                .opacity(isFlipped ? 0 : 1)
        }
        .onTapGesture {
            onFlip()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
    
    // MARK: - Card Front (Question/Term)
    
    private var cardFront: some View {
        VStack(spacing: 0) {
            // Card header
            HStack {
                Image(systemName: "rectangle.on.rectangle")
                    .foregroundStyle(deckColor)
                Text("FRONT")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(deckColor)
                Spacer()
                Image(systemName: "hand.tap")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            
            Spacer()
            
            // Question/Term
            Text(flashcard.front)
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            
            Spacer()
            
            // Source card
            Text("From: \(flashcard.sourceCardTitle)")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.15), radius: 10, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(deckColor.opacity(0.3), lineWidth: 2)
        )
    }
    
    // MARK: - Card Back (Answer/Explanation)
    
    private var cardBack: some View {
        VStack(spacing: 0) {
            // Card header
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("BACK")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.green)
                Spacer()
                Image(systemName: "hand.tap")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            
            Spacer()
            
            // Answer/Explanation
            ScrollView {
                Text(flashcard.back)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            
            Spacer()
            
            // Category if available
            if let category = flashcard.category {
                Text(category)
                    .font(.caption)
                    .foregroundStyle(deckColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(deckColor.opacity(0.15))
                    )
                    .padding(.bottom, 16)
            } else {
                Spacer().frame(height: 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.15), radius: 10, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.green.opacity(0.3), lineWidth: 2)
        )
    }
}

#Preview {
    FlashcardCardView(
        flashcard: Flashcard(
            front: "What is SwiftUI?",
            back: "SwiftUI is Apple's declarative framework for building user interfaces across all Apple platforms using Swift.",
            sourceCardTitle: "iOS Development Basics",
            category: "Frameworks"
        ),
        isFlipped: false,
        deckColor: .blue,
        onFlip: {}
    )
    .frame(height: 400)
    .padding()
}

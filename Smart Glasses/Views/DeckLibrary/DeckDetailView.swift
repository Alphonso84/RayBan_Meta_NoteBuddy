//
//  DeckDetailView.swift
//  Smart Glasses
//
//  Created by Claude on 1/22/26.
//

import SwiftUI
import SwiftData

/// Detail view for a deck showing cards in a carousel
struct DeckDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var deck: SummaryDeck

    @State private var selectedCardIndex = 0
    @State private var showingEditSheet = false

    @ObservedObject private var voiceFeedback = VoiceFeedbackManager.shared
    private var sortedCards: [SummaryCard] { deck.sortedCards }
    private var isPlaying: Bool { voiceFeedback.isSpeaking }

    var body: some View {
        ZStack {
            // Background with deck color
            deck.color.opacity(0.1)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if sortedCards.isEmpty {
                    emptyState
                } else {
                    // Card carousel
                    cardCarousel

                    // Card indicator
                    cardIndicator
                        .padding(.vertical, 16)

                    // Playback controls
                    playbackControls
                        .padding(.bottom, 16)
                }
            }
        }
        .navigationTitle(deck.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingEditSheet = true
                    } label: {
                        Label("Edit Deck", systemImage: "pencil")
                    }

                    if !sortedCards.isEmpty {
                        Button {
                            speakAllCards()
                        } label: {
                            Label("Read All Cards", systemImage: "speaker.wave.3")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            EditDeckSheet(deck: deck)
        }
        .onAppear {
            deck.markAccessed()
        }
        .onDisappear {
            voiceFeedback.stopSpeaking()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 64))
                .foregroundStyle(deck.color.opacity(0.5))

            Text("No Cards Yet")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Scan documents to add summary cards to this deck.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Card Carousel

    private var cardCarousel: some View {
        TabView(selection: $selectedCardIndex) {
            ForEach(Array(sortedCards.enumerated()), id: \.element.id) { index, card in
                CardCarouselItem(card: card, deckColor: deck.color)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(maxHeight: .infinity)
    }

    // MARK: - Card Indicator

    private var cardIndicator: some View {
        HStack(spacing: 8) {
            Text("\(selectedCardIndex + 1) / \(sortedCards.count)")
                .font(.subheadline)
                .fontWeight(.medium)
                .monospacedDigit()

            if sortedCards.count > 1 {
                HStack(spacing: 4) {
                    ForEach(0..<min(sortedCards.count, 10), id: \.self) { index in
                        Circle()
                            .fill(index == selectedCardIndex ? deck.color : Color(.systemGray4))
                            .frame(width: 6, height: 6)
                    }
                    if sortedCards.count > 10 {
                        Text("...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Playback Controls

    private var playbackControls: some View {
        HStack(spacing: 24) {
            // Previous
            Button {
                withAnimation {
                    selectedCardIndex = max(0, selectedCardIndex - 1)
                }
            } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(selectedCardIndex > 0 ? deck.color : Color(.systemGray4))
            }
            .disabled(selectedCardIndex == 0)

            // Play/Speak current card
            Button {
                if isPlaying {
                    voiceFeedback.stopSpeaking()
                } else {
                    speakCurrentCard()
                }
            } label: {
                Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(deck.color)
            }

            // Next
            Button {
                withAnimation {
                    selectedCardIndex = min(sortedCards.count - 1, selectedCardIndex + 1)
                }
            } label: {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(selectedCardIndex < sortedCards.count - 1 ? deck.color : Color(.systemGray4))
            }
            .disabled(selectedCardIndex >= sortedCards.count - 1)
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Actions

    private func speakCurrentCard() {
        guard selectedCardIndex < sortedCards.count else { return }
        let card = sortedCards[selectedCardIndex]
        voiceFeedback.speak(card.textForSpeech)
    }

    private func speakAllCards() {
        // Speak all cards by queuing them
        for card in sortedCards {
            voiceFeedback.speak(card.textForSpeech)
        }
    }
}


// MARK: - Card Carousel Item

struct CardCarouselItem: View {
    @Environment(\.modelContext) private var modelContext
    let card: SummaryCard
    let deckColor: Color

    @State private var showingDetail = false

    var body: some View {
        VStack(spacing: 0) {
            // Card content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header with thumbnail
                    HStack(alignment: .top, spacing: 12) {
                        if let thumbnailData = card.thumbnailData,
                           let uiImage = UIImage(data: thumbnailData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 70, height: 90)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(card.title)
                                .font(.title3)
                                .fontWeight(.bold)
                                .lineLimit(2)

                            Text(card.formattedDate)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if let pageNumber = card.pageNumber {
                                Text("Page \(pageNumber)")
                                    .font(.caption)
                                    .foregroundStyle(deckColor)
                            }
                        }

                        Spacer()
                    }

                    Divider()

                    // Summary
                    Text(card.summary)
                        .font(.body)
                        .lineSpacing(4)

                    // Key points
                    if !card.keyPoints.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Key Points")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)

                            ForEach(card.keyPoints, id: \.self) { point in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(deckColor)
                                        .font(.subheadline)
                                        .padding(.top, 1)

                                    Text(point)
                                        .font(.subheadline)
                                        .lineSpacing(2)
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        )
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .onTapGesture {
            showingDetail = true
        }
        .sheet(isPresented: $showingDetail) {
            CardDetailSheet(card: card)
        }
        .contextMenu {
            Button(role: .destructive) {
                deleteCard()
            } label: {
                Label("Delete Card", systemImage: "trash")
            }
        }
    }

    private func deleteCard() {
        modelContext.delete(card)
        try? modelContext.save()
    }
}

// MARK: - Edit Deck Sheet

struct EditDeckSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var deck: SummaryDeck

    @State private var title: String = ""
    @State private var description: String = ""
    @State private var selectedColor: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Deck Title", text: $title)
                    TextField("Description (optional)", text: $description)
                }

                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(SummaryDeck.presetColors, id: \.self) { colorHex in
                            Button {
                                selectedColor = colorHex
                            } label: {
                                Circle()
                                    .fill(Color(hex: colorHex) ?? .blue)
                                    .frame(width: 44, height: 44)
                                    .overlay {
                                        if selectedColor == colorHex {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(.white)
                                                .fontWeight(.bold)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                }

                Section {
                    HStack {
                        Text("Cards in Deck")
                        Spacer()
                        Text("\(deck.cardCount)")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Created")
                        Spacer()
                        Text(deck.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Edit Deck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveDeck()
                    }
                    .fontWeight(.semibold)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                title = deck.title
                description = deck.deckDescription ?? ""
                selectedColor = deck.colorHex
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func saveDeck() {
        deck.title = title.trimmingCharacters(in: .whitespaces)
        deck.deckDescription = description.isEmpty ? nil : description
        deck.colorHex = selectedColor

        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DeckDetailView(deck: SummaryDeck(
            title: "Swift Programming",
            colorHex: "007AFF",
            cards: [
                SummaryCard(
                    title: "Chapter 1: Basics",
                    summary: "Swift is a powerful and intuitive programming language. It combines the best in modern language thinking with wisdom from the wider Apple engineering culture.",
                    keyPoints: ["Type safety", "Modern syntax", "Performance"],
                    sourceText: "Full text here..."
                ),
                SummaryCard(
                    title: "Chapter 2: Functions",
                    summary: "Functions are self-contained chunks of code that perform a specific task. You give a function a name that identifies what it does.",
                    keyPoints: ["Named parameters", "Return values", "Closures"],
                    sourceText: "Full text here..."
                )
            ]
        ))
    }
    .modelContainer(for: [SummaryCard.self, SummaryDeck.self], inMemory: true)
}

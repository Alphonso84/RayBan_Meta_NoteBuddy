//
//  PDFImportView.swift
//  Smart Glasses
//
//  Import progress sheet for creating study cards from PDF pages
//

import SwiftUI
import SwiftData
import PDFKit

struct PDFImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let pdfURL: URL
    let targetDeck: SummaryDeck?
    var onComplete: (() -> Void)?

    @StateObject private var summarizer = StreamingSummarizer()

    // Provider recommendation alert
    @AppStorage("selectedProvider") private var selectedProvider: String = "apple"
    @AppStorage("hideOpenAIRecommendation") private var hideRecommendation = false
    @State private var showingProviderAlert = false

    @State private var importState: ImportState = .ready
    @State private var pages: [PDFImporter.PDFPage] = []
    @State private var pdfDocument: PDFDocument?
    @State private var currentPageIndex = 0
    @State private var completedPages: [(pageNumber: Int, title: String)] = []
    @State private var importTask: Task<Void, Never>?

    private var fileName: String {
        pdfURL.deletingPathExtension().lastPathComponent
    }

    enum ImportState: Equatable {
        case ready
        case importing
        case complete(Int)
        case error(String)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    switch importState {
                    case .ready:
                        readyView
                    case .importing:
                        importingView
                    case .complete(let count):
                        completeView(cardCount: count)
                    case .error(let message):
                        errorView(message: message)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Import PDF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        importTask?.cancel()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
        .alert("OpenAI Recommended", isPresented: $showingProviderAlert) {
            Button("Continue Anyway") { startImport() }
            Button("Switch to OpenAI") {
                selectedProvider = "openai"
                startImport()
            }
            Button("Don't Show Again", role: .cancel) {
                hideRecommendation = true
                startImport()
            }
        } message: {
            Text("PDF import processes multiple pages sequentially, which can exceed what the on-device model handles well. Switching to the OpenAI cloud model is recommended for better results.")
        }
        .onAppear {
            loadPDF()
        }
        .onDisappear {
            importTask?.cancel()
        }
    }

    // MARK: - Ready View

    private var readyView: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 56))
                .foregroundStyle(.blue)

            Text(fileName)
                .font(.title3)
                .fontWeight(.semibold)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            Text("\(pages.count) pages with text found")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let deck = targetDeck {
                Label("Adding to \"\(deck.title)\"", systemImage: "folder.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Label("Will create new deck", systemImage: "folder.badge.plus")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button {
                if selectedProvider == "apple" && !hideRecommendation {
                    showingProviderAlert = true
                } else {
                    startImport()
                }
            } label: {
                Label("Start Import", systemImage: "square.and.arrow.down")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(pages.isEmpty)
            .padding(.top, 8)
        }
        .padding(.vertical, 40)
    }

    // MARK: - Importing View

    private var importingView: some View {
        VStack(spacing: 20) {
            // Progress
            VStack(spacing: 8) {
                ProgressView(value: Double(completedPages.count), total: Double(pages.count))
                    .progressViewStyle(.linear)
                    .tint(.blue)

                Text("Summarizing page \(currentPageIndex + 1) of \(pages.count)...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Current page streaming summary
            if !summarizer.streamingSummary.isEmpty || !summarizer.suggestedTitle.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    if !summarizer.suggestedTitle.isEmpty {
                        Text(summarizer.suggestedTitle)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }

                    if !summarizer.streamingSummary.isEmpty {
                        Text(summarizer.streamingSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
            }

            // Completed pages list
            if !completedPages.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Completed")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    ForEach(completedPages, id: \.pageNumber) { page in
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)

                            Text("Page \(page.pageNumber)")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(page.title)
                                .font(.caption)
                                .fontWeight(.medium)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
            }
        }
    }

    // MARK: - Complete View

    private func completeView(cardCount: Int) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)

            Text("Import Complete!")
                .font(.title2)
                .fontWeight(.bold)

            Text("\(cardCount) cards created")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let deck = targetDeck {
                Text("Added to \"\(deck.title)\"")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Added to \"\(fileName)\"")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button {
                onComplete?()
                dismiss()
            } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.top, 8)
        }
        .padding(.vertical, 40)
    }

    // MARK: - Error View

    private func errorView(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.red)

            Text("Import Failed")
                .font(.title2)
                .fontWeight(.bold)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                dismiss()
            } label: {
                Text("Dismiss")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.top, 8)
        }
        .padding(.vertical, 40)
    }

    // MARK: - Actions

    private func loadPDF() {
        let result = PDFImporter.extractPages(from: pdfURL)
        pages = result.pages
        pdfDocument = result.document

        if pages.isEmpty {
            importState = .error("No text content found in this PDF.")
        }
    }

    private func startImport() {
        importState = .importing

        importTask = Task {
            // Determine which deck to use
            let deck: SummaryDeck
            if let existing = targetDeck {
                deck = existing
            } else {
                let newDeck = SummaryDeck(
                    title: fileName,
                    colorHex: SummaryDeck.randomColor
                )
                modelContext.insert(newDeck)
                deck = newDeck
            }

            var cardCount = 0

            for (index, page) in pages.enumerated() {
                if Task.isCancelled { break }

                currentPageIndex = index

                // Summarize the page text
                let summaryOutput = await summarizer.summarize(page.text)

                if Task.isCancelled { break }

                let title = summaryOutput?.suggestedTitle ?? "Page \(page.pageNumber)"
                let summary = summaryOutput?.summary ?? page.text.prefix(200).description
                let keyPoints = summaryOutput?.keyPoints ?? []

                // Generate thumbnail
                var thumbnailData: Data?
                if let pdfDoc = pdfDocument {
                    let thumbnail = PDFImporter.extractPageThumbnail(
                        from: pdfDoc,
                        pageIndex: page.pageNumber - 1
                    )
                    thumbnailData = thumbnail?.jpegData(compressionQuality: 0.6)
                }

                // Create the card
                let card = SummaryCard(
                    title: title,
                    summary: summary,
                    keyPoints: keyPoints,
                    sourceText: page.text,
                    pageNumber: page.pageNumber,
                    thumbnailData: thumbnailData,
                    deck: deck
                )

                modelContext.insert(card)
                deck.cards.append(card)
                cardCount += 1

                completedPages.append((pageNumber: page.pageNumber, title: title))
            }

            if !Task.isCancelled {
                deck.markAccessed()
                try? modelContext.save()
                importState = .complete(cardCount)
            }
        }
    }
}

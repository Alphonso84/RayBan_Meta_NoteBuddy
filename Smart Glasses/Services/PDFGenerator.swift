//
//  PDFGenerator.swift
//  Smart Glasses
//
//  PDF generation for exporting scanned documents
//

import UIKit
import PDFKit
import SwiftUI

/// Generates PDF documents from scanned card content
class PDFGenerator {

    // MARK: - PDF Configuration

    /// Standard US Letter size in points (8.5 x 11 inches)
    private static let pageWidth: CGFloat = 612
    private static let pageHeight: CGFloat = 792

    /// Margins
    private static let margin: CGFloat = 50
    private static let contentWidth: CGFloat = pageWidth - (margin * 2)

    // MARK: - Public Methods

    /// Generate a text-only PDF from a SummaryCard
    /// - Parameter card: The card to export
    /// - Returns: PDF data ready for sharing
    static func generatePDF(from card: SummaryCard) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))

        let data = renderer.pdfData { context in
            context.beginPage()

            var yPosition: CGFloat = margin

            // Draw title
            yPosition = drawTitle(card.title, at: yPosition, in: context)

            // Draw metadata (date)
            yPosition = drawMetadata(date: card.createdAt, pageNumber: card.pageNumber, at: yPosition, in: context)

            // Draw separator line
            yPosition = drawSeparator(at: yPosition, in: context)

            // Draw summary section
            yPosition = drawSectionHeader("Summary", at: yPosition, in: context)
            yPosition = drawBody(card.summary, at: yPosition, in: context)

            // Draw key points section if present
            if !card.keyPoints.isEmpty {
                yPosition += 20
                yPosition = drawSectionHeader("Key Points", at: yPosition, in: context)
                yPosition = drawKeyPoints(card.keyPoints, at: yPosition, in: context)
            }

            // Draw original text section
            yPosition += 20
            yPosition = drawSectionHeader("Original Text", at: yPosition, in: context)

            // Check if we need a new page for the original text
            let remainingHeight = pageHeight - yPosition - margin
            yPosition = drawOriginalText(card.sourceText, at: yPosition, remainingHeight: remainingHeight, in: context)

            // Draw footer
            drawFooter(in: context)
        }

        return data
    }

    /// Generate a PDF from raw text (for cards not yet saved)
    /// - Parameters:
    ///   - title: Document title
    ///   - summary: Summary text
    ///   - keyPoints: Array of key points
    ///   - sourceText: Original OCR text
    /// - Returns: PDF data ready for sharing
    static func generatePDF(
        title: String,
        summary: String,
        keyPoints: [String],
        sourceText: String
    ) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))

        let data = renderer.pdfData { context in
            context.beginPage()

            var yPosition: CGFloat = margin

            // Draw title
            yPosition = drawTitle(title, at: yPosition, in: context)

            // Draw metadata (current date)
            yPosition = drawMetadata(date: Date(), pageNumber: nil, at: yPosition, in: context)

            // Draw separator line
            yPosition = drawSeparator(at: yPosition, in: context)

            // Draw summary section
            if !summary.isEmpty {
                yPosition = drawSectionHeader("Summary", at: yPosition, in: context)
                yPosition = drawBody(summary, at: yPosition, in: context)
            }

            // Draw key points section if present
            if !keyPoints.isEmpty {
                yPosition += 20
                yPosition = drawSectionHeader("Key Points", at: yPosition, in: context)
                yPosition = drawKeyPoints(keyPoints, at: yPosition, in: context)
            }

            // Draw original text section
            yPosition += 20
            yPosition = drawSectionHeader("Original Text", at: yPosition, in: context)

            // Check if we need a new page for the original text
            let remainingHeight = pageHeight - yPosition - margin
            yPosition = drawOriginalText(sourceText, at: yPosition, remainingHeight: remainingHeight, in: context)

            // Draw footer
            drawFooter(in: context)
        }

        return data
    }

    // MARK: - Private Drawing Methods

    private static func drawTitle(_ title: String, at yPosition: CGFloat, in context: UIGraphicsPDFRendererContext) -> CGFloat {
        let titleFont = UIFont.systemFont(ofSize: 24, weight: .bold)
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: UIColor.black
        ]

        let titleRect = CGRect(x: margin, y: yPosition, width: contentWidth, height: 100)
        let attributedTitle = NSAttributedString(string: title, attributes: titleAttributes)

        let boundingRect = attributedTitle.boundingRect(
            with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )

        attributedTitle.draw(in: titleRect)

        return yPosition + boundingRect.height + 10
    }

    private static func drawMetadata(date: Date, pageNumber: Int?, at yPosition: CGFloat, in context: UIGraphicsPDFRendererContext) -> CGFloat {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .short

        var metadataText = "Scanned: \(dateFormatter.string(from: date))"
        if let pageNum = pageNumber {
            metadataText += " • Page \(pageNum)"
        }

        let metadataFont = UIFont.systemFont(ofSize: 12, weight: .regular)
        let metadataAttributes: [NSAttributedString.Key: Any] = [
            .font: metadataFont,
            .foregroundColor: UIColor.darkGray
        ]

        let metadataRect = CGRect(x: margin, y: yPosition, width: contentWidth, height: 20)
        metadataText.draw(in: metadataRect, withAttributes: metadataAttributes)

        return yPosition + 25
    }

    private static func drawSeparator(at yPosition: CGFloat, in context: UIGraphicsPDFRendererContext) -> CGFloat {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: margin, y: yPosition))
        path.addLine(to: CGPoint(x: pageWidth - margin, y: yPosition))

        UIColor.lightGray.setStroke()
        path.lineWidth = 1
        path.stroke()

        return yPosition + 20
    }

    private static func drawSectionHeader(_ text: String, at yPosition: CGFloat, in context: UIGraphicsPDFRendererContext) -> CGFloat {
        let headerFont = UIFont.systemFont(ofSize: 14, weight: .semibold)
        let headerAttributes: [NSAttributedString.Key: Any] = [
            .font: headerFont,
            .foregroundColor: UIColor.darkGray
        ]

        let headerRect = CGRect(x: margin, y: yPosition, width: contentWidth, height: 20)
        text.draw(in: headerRect, withAttributes: headerAttributes)

        return yPosition + 25
    }

    private static func drawBody(_ text: String, at yPosition: CGFloat, in context: UIGraphicsPDFRendererContext) -> CGFloat {
        let bodyFont = UIFont.systemFont(ofSize: 12, weight: .regular)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4

        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: UIColor.black,
            .paragraphStyle: paragraphStyle
        ]

        let attributedText = NSAttributedString(string: text, attributes: bodyAttributes)
        let boundingRect = attributedText.boundingRect(
            with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )

        let bodyRect = CGRect(x: margin, y: yPosition, width: contentWidth, height: boundingRect.height)
        attributedText.draw(in: bodyRect)

        return yPosition + boundingRect.height + 10
    }

    private static func drawKeyPoints(_ points: [String], at yPosition: CGFloat, in context: UIGraphicsPDFRendererContext) -> CGFloat {
        var currentY = yPosition

        let bulletFont = UIFont.systemFont(ofSize: 12, weight: .regular)
        let bulletAttributes: [NSAttributedString.Key: Any] = [
            .font: bulletFont,
            .foregroundColor: UIColor.black
        ]

        for point in points {
            let bulletText = "• \(point)"
            let attributedText = NSAttributedString(string: bulletText, attributes: bulletAttributes)

            let boundingRect = attributedText.boundingRect(
                with: CGSize(width: contentWidth - 20, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )

            let pointRect = CGRect(x: margin + 10, y: currentY, width: contentWidth - 20, height: boundingRect.height)
            attributedText.draw(in: pointRect)

            currentY += boundingRect.height + 8
        }

        return currentY
    }

    private static func drawOriginalText(_ text: String, at yPosition: CGFloat, remainingHeight: CGFloat, in context: UIGraphicsPDFRendererContext) -> CGFloat {
        let bodyFont = UIFont.systemFont(ofSize: 10, weight: .regular)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 3

        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: UIColor.darkGray,
            .paragraphStyle: paragraphStyle
        ]

        let attributedText = NSAttributedString(string: text, attributes: bodyAttributes)
        let fullBoundingRect = attributedText.boundingRect(
            with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )

        var currentY = yPosition

        // If text fits on current page, draw it
        if fullBoundingRect.height <= remainingHeight {
            let bodyRect = CGRect(x: margin, y: currentY, width: contentWidth, height: fullBoundingRect.height)
            attributedText.draw(in: bodyRect)
            return currentY + fullBoundingRect.height
        }

        // Otherwise, we need to handle pagination
        // For simplicity, draw what fits and add continuation note
        let fitRect = CGRect(x: margin, y: currentY, width: contentWidth, height: remainingHeight - 30)
        attributedText.draw(in: fitRect)

        // Add continuation indicator
        let continueFont = UIFont.italicSystemFont(ofSize: 10)
        let continueAttributes: [NSAttributedString.Key: Any] = [
            .font: continueFont,
            .foregroundColor: UIColor.gray
        ]
        let continueText = "[Text continues...]"
        let continueRect = CGRect(x: margin, y: pageHeight - margin - 20, width: contentWidth, height: 20)
        continueText.draw(in: continueRect, withAttributes: continueAttributes)

        // Start new page for remaining content
        context.beginPage()
        currentY = margin

        // Draw remaining text (simplified - just redraw all on new page)
        let newPageRect = CGRect(x: margin, y: currentY, width: contentWidth, height: pageHeight - (margin * 2) - 30)
        attributedText.draw(in: newPageRect)

        return currentY + min(fullBoundingRect.height, pageHeight - (margin * 2) - 30)
    }

    private static func drawFooter(in context: UIGraphicsPDFRendererContext) {
        let footerFont = UIFont.systemFont(ofSize: 9, weight: .regular)
        let footerAttributes: [NSAttributedString.Key: Any] = [
            .font: footerFont,
            .foregroundColor: UIColor.lightGray
        ]

        let footerText = "Generated by Smart Glasses App"
        let footerRect = CGRect(x: margin, y: pageHeight - margin + 10, width: contentWidth, height: 20)
        footerText.draw(in: footerRect, withAttributes: footerAttributes)
    }

    // MARK: - Flashcard PDF Generation

    /// Generate a printable PDF with flashcards arranged for printing
    /// Layout: 4 cards per page (2x2 grid), with fronts on one page and backs on the next
    /// - Parameters:
    ///   - flashcards: Array of flashcards to print
    ///   - deckTitle: Title of the deck for the header
    ///   - deckColor: Color theme for accents
    /// - Returns: PDF data ready for printing/sharing
    static func generateFlashcardPDF(flashcards: [Flashcard], deckTitle: String, deckColor: Color) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))

        // Card dimensions for 2x2 grid with margins
        let cardWidth: CGFloat = (contentWidth - 20) / 2  // 20pt gap between cards
        let cardHeight: CGFloat = 280  // Enough for content
        let cardsPerPage = 4

        let uiColor = UIColor(deckColor)

        let data = renderer.pdfData { context in
            var cardIndex = 0

            while cardIndex < flashcards.count {
                // Front page
                context.beginPage()
                drawFlashcardPageHeader(deckTitle, subtitle: "Front Side", page: (cardIndex / cardsPerPage) + 1, in: context)

                for i in 0..<cardsPerPage {
                    guard cardIndex + i < flashcards.count else { break }
                    let flashcard = flashcards[cardIndex + i]
                    let position = cardPosition(for: i, cardWidth: cardWidth, cardHeight: cardHeight)
                    drawFlashcardFront(flashcard, at: position, size: CGSize(width: cardWidth, height: cardHeight), color: uiColor, in: context)
                }

                drawFooter(in: context)

                // Back page (mirrored for double-sided printing)
                context.beginPage()
                drawFlashcardPageHeader(deckTitle, subtitle: "Back Side", page: (cardIndex / cardsPerPage) + 1, in: context)

                for i in 0..<cardsPerPage {
                    guard cardIndex + i < flashcards.count else { break }
                    let flashcard = flashcards[cardIndex + i]
                    // Mirror positions horizontally for correct alignment when printed double-sided
                    let mirroredIndex = (i % 2 == 0) ? i + 1 : i - 1
                    let position = cardPosition(for: mirroredIndex, cardWidth: cardWidth, cardHeight: cardHeight)
                    drawFlashcardBack(flashcard, at: position, size: CGSize(width: cardWidth, height: cardHeight), color: uiColor, in: context)
                }

                drawFooter(in: context)

                cardIndex += cardsPerPage
            }
        }

        return data
    }

    private static func cardPosition(for index: Int, cardWidth: CGFloat, cardHeight: CGFloat) -> CGPoint {
        let row = index / 2
        let col = index % 2

        let x = margin + CGFloat(col) * (cardWidth + 20)
        let y: CGFloat = 100 + CGFloat(row) * (cardHeight + 20)  // 100pt for header

        return CGPoint(x: x, y: y)
    }

    private static func drawFlashcardPageHeader(_ title: String, subtitle: String, page: Int, in context: UIGraphicsPDFRendererContext) {
        let titleFont = UIFont.systemFont(ofSize: 18, weight: .bold)
        let subtitleFont = UIFont.systemFont(ofSize: 12, weight: .medium)

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: UIColor.black
        ]

        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: subtitleFont,
            .foregroundColor: UIColor.gray
        ]

        title.draw(at: CGPoint(x: margin, y: margin), withAttributes: titleAttributes)
        "\(subtitle) - Page \(page)".draw(at: CGPoint(x: margin, y: margin + 25), withAttributes: subtitleAttributes)
    }

    private static func drawFlashcardFront(_ flashcard: Flashcard, at origin: CGPoint, size: CGSize, color: UIColor, in context: UIGraphicsPDFRendererContext) {
        // Draw card border
        let cardRect = CGRect(origin: origin, size: size)
        let path = UIBezierPath(roundedRect: cardRect, cornerRadius: 12)

        UIColor.systemGray6.setFill()
        path.fill()

        color.withAlphaComponent(0.3).setStroke()
        path.lineWidth = 2
        path.stroke()

        // Draw "FRONT" label
        let labelFont = UIFont.systemFont(ofSize: 10, weight: .semibold)
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: color
        ]
        "FRONT".draw(at: CGPoint(x: origin.x + 12, y: origin.y + 10), withAttributes: labelAttributes)

        // Draw question/term
        let textFont = UIFont.systemFont(ofSize: 14, weight: .semibold)
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: textFont,
            .foregroundColor: UIColor.black
        ]

        let textRect = CGRect(
            x: origin.x + 16,
            y: origin.y + 40,
            width: size.width - 32,
            height: size.height - 80
        )

        let attributedText = NSAttributedString(string: flashcard.front, attributes: textAttributes)
        attributedText.draw(in: textRect)

        // Draw source card at bottom
        let sourceFont = UIFont.systemFont(ofSize: 9, weight: .regular)
        let sourceAttributes: [NSAttributedString.Key: Any] = [
            .font: sourceFont,
            .foregroundColor: UIColor.lightGray
        ]
        let sourceText = "From: \(flashcard.sourceCardTitle)"
        let sourceRect = CGRect(x: origin.x + 12, y: origin.y + size.height - 25, width: size.width - 24, height: 20)
        sourceText.draw(in: sourceRect, withAttributes: sourceAttributes)
    }

    private static func drawFlashcardBack(_ flashcard: Flashcard, at origin: CGPoint, size: CGSize, color: UIColor, in context: UIGraphicsPDFRendererContext) {
        // Draw card border
        let cardRect = CGRect(origin: origin, size: size)
        let path = UIBezierPath(roundedRect: cardRect, cornerRadius: 12)

        UIColor.systemGray6.setFill()
        path.fill()

        UIColor.systemGreen.withAlphaComponent(0.5).setStroke()
        path.lineWidth = 2
        path.stroke()

        // Draw "BACK" label
        let labelFont = UIFont.systemFont(ofSize: 10, weight: .semibold)
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: UIColor.systemGreen
        ]
        "BACK".draw(at: CGPoint(x: origin.x + 12, y: origin.y + 10), withAttributes: labelAttributes)

        // Draw answer
        let textFont = UIFont.systemFont(ofSize: 12, weight: .regular)
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: textFont,
            .foregroundColor: UIColor.darkGray
        ]

        let textRect = CGRect(
            x: origin.x + 16,
            y: origin.y + 40,
            width: size.width - 32,
            height: size.height - 80
        )

        let attributedText = NSAttributedString(string: flashcard.back, attributes: textAttributes)
        attributedText.draw(in: textRect)

        // Draw category at bottom if available
        if let category = flashcard.category {
            let categoryFont = UIFont.systemFont(ofSize: 9, weight: .medium)
            let categoryAttributes: [NSAttributedString.Key: Any] = [
                .font: categoryFont,
                .foregroundColor: color
            ]
            let categoryRect = CGRect(x: origin.x + 12, y: origin.y + size.height - 25, width: size.width - 24, height: 20)
            category.draw(in: categoryRect, withAttributes: categoryAttributes)
        }
    }
}

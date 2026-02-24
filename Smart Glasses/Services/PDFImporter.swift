//
//  PDFImporter.swift
//  Smart Glasses
//
//  PDF text extraction and thumbnail rendering using PDFKit
//

import PDFKit
import UIKit

struct PDFImporter {

    struct PDFPage {
        let pageNumber: Int
        let text: String
    }

    /// Extract text from each page of a PDF file
    /// - Parameter url: The URL of the PDF file (may be security-scoped from file picker)
    /// - Returns: Array of pages with extracted text, filtering out pages with < 30 characters
    static func extractPages(from url: URL) -> (pages: [PDFPage], document: PDFDocument?) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let document = PDFDocument(url: url) else {
            return ([], nil)
        }

        var pages: [PDFPage] = []

        for i in 0..<document.pageCount {
            guard let page = document.page(at: i),
                  let text = page.string,
                  text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 30 else {
                continue
            }

            pages.append(PDFPage(
                pageNumber: i + 1,
                text: text.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        }

        return (pages, document)
    }

    /// Render a thumbnail image of a PDF page
    /// - Parameters:
    ///   - pdfDocument: The PDFDocument to render from
    ///   - pageIndex: Zero-based page index
    ///   - maxSize: Maximum dimension for the thumbnail
    /// - Returns: A UIImage thumbnail, or nil if the page doesn't exist
    static func extractPageThumbnail(from pdfDocument: PDFDocument, pageIndex: Int, maxSize: CGFloat = 300) -> UIImage? {
        guard let page = pdfDocument.page(at: pageIndex) else { return nil }
        return page.thumbnail(of: CGSize(width: maxSize, height: maxSize), for: .mediaBox)
    }
}

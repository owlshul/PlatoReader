import Foundation
import PDFKit
import Vision
import Cocoa

public struct PDFContextResult {
    public let pageNumber: Int
    public let endPageNumber: Int?
    public let totalPages: Int
    public let pageText: String
    public let documentName: String

    public var pageDisplay: String {
        if let end = endPageNumber, end != pageNumber {
            return "Pages \(pageNumber)–\(end)"
        } else {
            return "Page \(pageNumber)"
        }
    }
}

public class PDFContextHelper {
    public static let shared = PDFContextHelper()

    private init() {}

    public func extractContext(documentPath: String?, windowTitle: String?, selection: String) -> PDFContextResult? {
        var filePath = documentPath

        if filePath == nil || filePath?.isEmpty == true {
            filePath = getPreviewFrontDocumentPath()
        }

        guard let path = filePath, !path.isEmpty else {
            return nil
        }

        let fileURL = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let pdfDocument = PDFDocument(url: fileURL) else {
            return nil
        }

        let totalPages = pdfDocument.pageCount
        guard totalPages > 0 else { return nil }
        let docName = fileURL.lastPathComponent

        // 1. Try to extract current page index directly from window title (e.g. "Page 5 of 512" or "Page 5")
        var targetPageIndex: Int? = nil
        if let title = windowTitle {
            if let match = title.range(of: "Page\\s+(\\d+)", options: [.regularExpression, .caseInsensitive]) {
                let sub = title[match]
                let digits = sub.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
                if let pageNum = Int(digits), pageNum >= 1 && pageNum <= totalPages {
                    targetPageIndex = pageNum - 1
                }
            }
        }

        // 2. If target page index was found from title, extract that page and check for two-page span
        if let pIndex = targetPageIndex, let page = pdfDocument.page(at: pIndex) {
            let extracted = extractTextFromPage(page)
            if !extracted.isEmpty {
                return checkTwoPageSpan(
                    pIndex: pIndex,
                    pdfDocument: pdfDocument,
                    docName: docName,
                    totalPages: totalPages,
                    firstPageText: extracted,
                    selection: selection
                )
            }
        }

        // 3. Fallback: Search PDF via findString for the selection snippet
        let cleanSelection = selection.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")

        let words = cleanSelection.components(separatedBy: " ").filter { $0.count >= 4 }
        let searchSnippet = words.prefix(3).joined(separator: " ")

        if !searchSnippet.isEmpty {
            let matches = pdfDocument.findString(searchSnippet, withOptions: .caseInsensitive)
            if let firstMatch = matches.first, let matchPage = firstMatch.pages.first {
                let pIndex = pdfDocument.index(for: matchPage)
                let extracted = extractTextFromPage(matchPage)
                return checkTwoPageSpan(
                    pIndex: pIndex,
                    pdfDocument: pdfDocument,
                    docName: docName,
                    totalPages: totalPages,
                    firstPageText: extracted,
                    selection: selection
                )
            }
        }

        // 4. If target page index was found but digital text was empty, run Vision OCR and check two-page span
        if let pIndex = targetPageIndex, let page = pdfDocument.page(at: pIndex) {
            let extracted = extractTextViaVisionOCR(page: page)
            return checkTwoPageSpan(
                pIndex: pIndex,
                pdfDocument: pdfDocument,
                docName: docName,
                totalPages: totalPages,
                firstPageText: extracted,
                selection: selection
            )
        }

        return nil
    }

    // MARK: - Multi-Page Span Detection
    private func checkTwoPageSpan(
        pIndex: Int,
        pdfDocument: PDFDocument,
        docName: String,
        totalPages: Int,
        firstPageText: String,
        selection: String
    ) -> PDFContextResult {
        let cleanSel = selection.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
        let selWords = cleanSel.components(separatedBy: " ")
            .map { $0.trimmingCharacters(in: CharacterSet.alphanumerics.inverted).lowercased() }
            .filter { $0.count >= 3 }

        let stopWords: Set<String> = [
            "the", "and", "that", "this", "with", "from", "were", "was", "are", "been",
            "have", "has", "had", "they", "them", "their", "what", "when", "where", "which",
            "who", "whom", "will", "would", "could", "should", "than", "then", "into", "only", "also", "about", "more"
        ]

        let contentWords = selWords.filter { !stopWords.contains($0) && $0.count >= 3 }
        guard contentWords.count >= 4 else {
            // Short selection, single page is sufficient
            return PDFContextResult(
                pageNumber: pIndex + 1,
                endPageNumber: nil,
                totalPages: totalPages,
                pageText: firstPageText,
                documentName: docName
            )
        }

        let firstWords = Array(contentWords.prefix(3))
        let lastWords = Array(contentWords.suffix(3))

        let pageLower = firstPageText.lowercased()

        // If the full selection is already contained inside this page, single page is enough
        if pageLower.contains(cleanSel.lowercased()) {
            return PDFContextResult(
                pageNumber: pIndex + 1,
                endPageNumber: nil,
                totalPages: totalPages,
                pageText: firstPageText,
                documentName: docName
            )
        }

        let firstMatchCount = firstWords.filter { pageLower.contains($0) }.count
        let lastMatchCount = lastWords.filter { pageLower.contains($0) }.count

        // Case 1: Start words are on page pIndex, but end words are on the next page (pIndex + 1)
        if pIndex + 1 < totalPages && firstMatchCount >= 2 && lastMatchCount <= 1 {
            if let nextPage = pdfDocument.page(at: pIndex + 1) {
                let nextText = extractTextFromPage(nextPage)
                let nextLower = nextText.lowercased()
                let nextLastMatchCount = lastWords.filter { nextLower.contains($0) }.count
                if nextLastMatchCount >= 1 {
                    let combined = """
                    --- Page \(pIndex + 1) ---
                    \(firstPageText)

                    --- Page \(pIndex + 2) ---
                    \(nextText)
                    """
                    return PDFContextResult(
                        pageNumber: pIndex + 1,
                        endPageNumber: pIndex + 2,
                        totalPages: totalPages,
                        pageText: combined,
                        documentName: docName
                    )
                }
            }
        }

        // Case 2: End words are on page pIndex, but start words were on the previous page (pIndex - 1)
        if pIndex - 1 >= 0 && lastMatchCount >= 2 && firstMatchCount <= 1 {
            if let prevPage = pdfDocument.page(at: pIndex - 1) {
                let prevText = extractTextFromPage(prevPage)
                let prevLower = prevText.lowercased()
                let prevFirstMatchCount = firstWords.filter { prevLower.contains($0) }.count
                if prevFirstMatchCount >= 1 {
                    let combined = """
                    --- Page \(pIndex) ---
                    \(prevText)

                    --- Page \(pIndex + 1) ---
                    \(firstPageText)
                    """
                    return PDFContextResult(
                        pageNumber: pIndex,
                        endPageNumber: pIndex + 1,
                        totalPages: totalPages,
                        pageText: combined,
                        documentName: docName
                    )
                }
            }
        }

        // Default single page
        return PDFContextResult(
            pageNumber: pIndex + 1,
            endPageNumber: nil,
            totalPages: totalPages,
            pageText: firstPageText,
            documentName: docName
        )
    }

    private func extractTextFromPage(_ page: PDFPage) -> String {
        // If digital text is available, use it directly (instant)
        if let digitalText = page.string, digitalText.trimmingCharacters(in: .whitespacesAndNewlines).count > 40 {
            return cleanExtractedText(digitalText)
        }

        // Otherwise (scanned PDF / image), use Apple Vision OCR
        return extractTextViaVisionOCR(page: page)
    }

    private func extractTextViaVisionOCR(page: PDFPage) -> String {
        let pageRect = page.bounds(for: .mediaBox)
        guard pageRect.width > 0 && pageRect.height > 0 else { return "" }

        let renderer = NSImage(size: pageRect.size)
        renderer.lockFocus()
        if let context = NSGraphicsContext.current?.cgContext {
            context.setFillColor(NSColor.white.cgColor)
            context.fill(pageRect)
            page.draw(with: .mediaBox, to: context)
        }
        renderer.unlockFocus()

        guard let tiffData = renderer.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let cgImage = bitmap.cgImage else {
            return ""
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])

        var lines: [String] = []
        if let results = request.results {
            for observation in results {
                if let top = observation.topCandidates(1).first {
                    lines.append(top.string)
                }
            }
        }

        return cleanExtractedText(lines.joined(separator: "\n"))
    }

    private func cleanExtractedText(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.joined(separator: "\n")
    }

    private func getPreviewFrontDocumentPath() -> String? {
        let script = """
        tell application "System Events"
            if exists process "Preview" then
                tell application "Preview"
                    if (count of documents) > 0 then
                        return path of front document
                    end if
                end tell
            end if
        end tell
        """
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            let output = appleScript.executeAndReturnError(&error)
            if let path = output.stringValue, !path.isEmpty {
                return path
            }
        }
        return nil
    }
}

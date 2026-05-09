import AppKit
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import Vision

actor CaptureService {
    func extractText(from url: URL) async throws -> (type: CaptureType, text: String, assetPath: String?) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        try LibraryPaths.ensure()
        try validateFileSize(url)
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" {
            return try extractPDF(url)
        }
        if ["png", "jpg", "jpeg", "heic", "tiff", "webp"].contains(ext) {
            return try await extractImage(url)
        }
        let text = try String(contentsOf: url, encoding: .utf8)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AIError.message("The selected file did not contain readable text.")
        }
        return (.manualText, String(trimmed.prefix(CaptureImportPolicy.maxExtractedCharacters)), nil)
    }

    func extractWebText(from rawURL: String) async throws -> String {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            throw AIError.message("Enter a valid http or https URL.")
        }

        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("NavRead/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw AIError.message("The web page could not be loaded.")
        }
        if data.count > CaptureImportPolicy.maxWebBytes {
            throw AIError.message("The web page is too large to import.")
        }
        if let mime = http.mimeType?.lowercased(),
           !mime.contains("html"),
           !mime.contains("text"),
           !mime.contains("xml") {
            throw AIError.message("The URL did not return readable text.")
        }

        let html = String(decoding: data, as: UTF8.self)
        let text = html
            .replacingOccurrences(of: "<script[\\s\\S]*?</script>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "<style[\\s\\S]*?</style>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let decoded = decodeHTMLEntities(text)
        guard !decoded.isEmpty else {
            throw AIError.message("No readable text was found at that URL.")
        }
        return String(decoded.prefix(CaptureImportPolicy.maxExtractedCharacters))
    }

    private func extractPDF(_ url: URL) throws -> (CaptureType, String, String?) {
        guard let document = PDFDocument(url: url) else {
            throw AIError.message("The PDF could not be opened.")
        }
        guard !document.isEncrypted else {
            throw AIError.message("Encrypted PDFs are not supported yet.")
        }
        guard document.pageCount > 0 else {
            throw AIError.message("The PDF has no pages.")
        }

        var pages: [String] = []
        let pageLimit = min(document.pageCount, CaptureImportPolicy.maxPDFPages)
        for index in 0..<pageLimit {
            guard let page = document.page(at: index) else { continue }
            if let text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                pages.append("[page \(index + 1)]\n\(text)")
            } else if let ocrText = try? ocr(page: page), !ocrText.isEmpty {
                pages.append("[page \(index + 1)]\n\(ocrText)")
            }
        }
        let text = pages.joined(separator: "\n\n")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIError.message("No readable text was found in this PDF.")
        }
        let stored = try copyCaptureAsset(url)
        return (.pdfPage, String(text.prefix(CaptureImportPolicy.maxExtractedCharacters)), stored.path)
    }

    private func extractImage(_ url: URL) async throws -> (CaptureType, String, String?) {
        let loaded = try loadImage(at: url)
        let text = try recognizeText(in: loaded.image, orientation: loaded.orientation)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIError.message("No readable text was found in this image.")
        }
        let stored = try copyCaptureAsset(url)
        return (.imageFile, String(text.prefix(CaptureImportPolicy.maxExtractedCharacters)), stored.path)
    }

    private func recognizeText(in cgImage: CGImage, orientation: CGImagePropertyOrientation = .up) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
        try handler.perform([request])
        return request.results?
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n") ?? ""
    }

    private func ocr(page: PDFPage) throws -> String {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return "" }
        let pixelBudget = CGFloat(CaptureImportPolicy.maxImagePixels)
        let scale = min(2.0, max(0.75, sqrt(pixelBudget / max(1, bounds.width * bounds.height))))
        let size = NSSize(width: bounds.width * scale, height: bounds.height * scale)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        guard let context = NSGraphicsContext.current?.cgContext else { return "" }
        context.saveGState()
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)
        context.restoreGState()
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return "" }
        return try recognizeText(in: cgImage)
    }

    private func copyCaptureAsset(_ url: URL) throws -> URL {
        let destination = LibraryPaths.captures.appendingPathComponent("\(UUID().uuidString).\(url.pathExtension)")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: url, to: destination)
        return destination
    }

    private func validateFileSize(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        if let size = values.fileSize, size > CaptureImportPolicy.maxFileBytes {
            throw AIError.message("Files must be 25 MB or smaller.")
        }
    }

    private func loadImage(at url: URL) throws -> (image: CGImage, orientation: CGImagePropertyOrientation) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw AIError.message("The image could not be opened.")
        }
        let pixelCount = image.width * image.height
        guard pixelCount <= CaptureImportPolicy.maxImagePixels else {
            throw AIError.message("The image is too large to OCR.")
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let rawOrientation = properties?[kCGImagePropertyOrientation] as? UInt32
        return (image, CGImagePropertyOrientation(rawValue: rawOrientation ?? 1) ?? .up)
    }

    private func decodeHTMLEntities(_ value: String) -> String {
        guard let data = value.data(using: .utf8),
              let attributed = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
              ) else {
            return value
        }
        return attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum ExportService {
    struct Bundle: Codable {
        var book: Book
        var chapters: [Chapter]
        var quotes: [Quote]
        var captures: [Capture]
    }

    static func json(book: Book, chapters: [Chapter], quotes: [Quote], captures: [Capture]) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let bundle = Bundle(book: book, chapters: chapters, quotes: quotes, captures: captures)
        guard let data = try? encoder.encode(bundle) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    static func csv(book: Book, chapters: [Chapter], quotes: [Quote]) -> String {
        let rows = quotes.map { quote in
            let chapter = chapters.first { $0.id == quote.chapterID }
            return [
                book.title,
                book.author,
                chapter?.title ?? "",
                quote.pageLocator,
                quote.text,
                quote.tags.joined(separator: ";"),
                quote.note,
                quote.sourceType.rawValue,
                quote.sourceURL
            ].map(csvEscape).joined(separator: ",")
        }
        let header = ["book", "author", "chapter", "page", "quote", "tags", "note", "source_type", "source_url"].joined(separator: ",")
        return ([header] + rows).joined(separator: "\n")
    }

    static func markdown(book: Book, chapters: [Chapter], quotes: [Quote]) -> String {
        var output = "# \(book.title)\n\n"
        if !book.author.isEmpty { output += "_\(book.author)_\n\n" }
        if !book.summary.isEmpty {
            output += "\(book.summary)\n\n"
        }
        if !book.learnings.isEmpty {
            output += "## Book Learnings\n\n\(book.learnings)\n\n"
        }
        var exportedQuoteIDs = Set<UUID>()
        for chapter in chapters {
            output += "## \(chapter.title)\n\n"
            if !chapter.learnings.isEmpty {
                output += "### Chapter Learnings\n\n\(chapter.learnings)\n\n"
            }
            let chapterQuotes = quotes.filter { $0.chapterID == chapter.id }
            for quote in chapterQuotes {
                exportedQuoteIDs.insert(quote.id)
                output += "> \(quote.text)\n\n"
                if !quote.pageLocator.isEmpty { output += "`\(quote.pageLocator)`\n\n" }
                if !quote.note.isEmpty { output += "\(quote.note)\n\n" }
            }
        }
        let unassigned = quotes.filter { !exportedQuoteIDs.contains($0.id) }
        if !unassigned.isEmpty {
            output += "## Unassigned\n\n"
            for quote in unassigned {
                output += "> \(quote.text)\n\n"
                if !quote.pageLocator.isEmpty { output += "`\(quote.pageLocator)`\n\n" }
                if !quote.note.isEmpty { output += "\(quote.note)\n\n" }
            }
        }
        return output
    }

    static func htmlNote(book: Book, chapters: [Chapter], quotes: [Quote]) -> String {
        let markdown = markdown(book: book, chapters: chapters, quotes: quotes)
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return """
        <h1>\(book.title)</h1>
        <p><em>\(book.displayAuthor)</em></p>
        <pre style="font-family:-apple-system;white-space:pre-wrap;">\(markdown)</pre>
        """
    }

    private static func csvEscape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}

enum ExportFormat: String, CaseIterable, Identifiable {
    case markdown
    case json
    case csv

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .markdown: "Markdown"
        case .json: "JSON"
        case .csv: "CSV"
        }
    }

    var fileExtension: String {
        switch self {
        case .markdown: "md"
        case .json: "json"
        case .csv: "csv"
        }
    }

    var contentType: UTType {
        switch self {
        case .markdown: .plainText
        case .json: .json
        case .csv: .commaSeparatedText
        }
    }

    var icon: String {
        switch self {
        case .markdown: "doc.richtext"
        case .json: "curlybraces"
        case .csv: "tablecells"
        }
    }
}

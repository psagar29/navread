import AppKit
import Foundation
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
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" {
            return try extractPDF(url)
        }
        if ["png", "jpg", "jpeg", "heic", "tiff", "webp"].contains(ext) {
            return try await extractImage(url)
        }
        let text = try String(contentsOf: url, encoding: .utf8)
        return (.manualText, text, nil)
    }

    func extractWebText(from rawURL: String) async throws -> String {
        guard let url = URL(string: rawURL) else { return "" }
        let (data, _) = try await URLSession.shared.data(from: url)
        let html = String(decoding: data, as: UTF8.self)
        return html
            .replacingOccurrences(of: "<script[\\s\\S]*?</script>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "<style[\\s\\S]*?</style>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractPDF(_ url: URL) throws -> (CaptureType, String, String?) {
        guard let document = PDFDocument(url: url) else {
            return (.pdfPage, "", nil)
        }
        var pages: [String] = []
        for index in 0..<document.pageCount {
            if let text = document.page(at: index)?.string, !text.isEmpty {
                pages.append("[page \(index + 1)]\n\(text)")
            }
        }
        let stored = try copyCaptureAsset(url)
        return (.pdfPage, pages.joined(separator: "\n\n"), stored.path)
    }

    private func extractImage(_ url: URL) async throws -> (CaptureType, String, String?) {
        let stored = try copyCaptureAsset(url)
        guard let cgImage = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return (.imageFile, "", stored.path)
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: cgImage)
        try handler.perform([request])
        let text = request.results?
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n") ?? ""
        return (.imageFile, text, stored.path)
    }

    private func copyCaptureAsset(_ url: URL) throws -> URL {
        let destination = LibraryPaths.captures.appendingPathComponent("\(UUID().uuidString).\(url.pathExtension)")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: url, to: destination)
        return destination
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
        output += "\(book.summary)\n\n"
        for chapter in chapters {
            output += "## \(chapter.title)\n\n"
            let chapterQuotes = quotes.filter { $0.chapterID == chapter.id }
            for quote in chapterQuotes {
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

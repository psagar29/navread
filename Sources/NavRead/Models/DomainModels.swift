import Foundation
import SwiftUI

enum SourceType: String, Codable, CaseIterable, Identifiable {
    case manual
    case screenshot
    case image
    case pdf
    case web
    case clipboard

    var id: String { rawValue }
}

enum CaptureType: String, Codable, CaseIterable, Identifiable {
    case manualText
    case screenshot
    case imageFile
    case pdfPage
    case webURL

    var id: String { rawValue }
}

enum AIScope: String, Codable, CaseIterable, Identifiable {
    case library
    case book
    case chapter
    case quote
    case capture

    var id: String { rawValue }
}

struct Book: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var nickname: String
    var author: String
    var isbn: String
    var summary: String
    var learnings: String
    var coverAssetPath: String?
    var dominantHex: String
    var metadataSource: String
    var createdAt: Date
    var updatedAt: Date

    var displayTitle: String {
        nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? title : nickname
    }

    var displayAuthor: String {
        author.isEmpty ? "Unknown author" : author
    }
}

struct Chapter: Identifiable, Codable, Hashable {
    var id: UUID
    var bookID: UUID
    var title: String
    var orderIndex: Int
    var summary: String
    var learnings: String
    var pageStart: Int?
    var pageEnd: Int?
    var aiGenerated: Bool
    var createdAt: Date
    var updatedAt: Date
}

struct Quote: Identifiable, Codable, Hashable {
    var id: UUID
    var bookID: UUID
    var chapterID: UUID?
    var rawText: String
    var cleanedText: String
    var pageLocator: String
    var note: String
    var tags: [String]
    var sourceType: SourceType
    var sourceURL: String
    var captureID: UUID?
    var createdAt: Date
    var updatedAt: Date

    var text: String {
        cleanedText.isEmpty ? rawText : cleanedText
    }
}

struct SavedQuote: Identifiable, Codable, Hashable {
    var id: UUID
    var text: String
    var author: String
    var source: String
    var note: String
    var tags: [String]
    var createdAt: Date
    var updatedAt: Date

    var attribution: String {
        let parts = [author, source]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? "Saved quote" : parts.joined(separator: " / ")
    }
}

struct SavedQuoteCandidate: Identifiable, Codable, Hashable {
    var id = UUID()
    var text: String
    var author: String
    var source: String
    var note: String
    var tags: [String]
    var confidence: Double
}

struct Capture: Identifiable, Codable, Hashable {
    var id: UUID
    var bookID: UUID
    var chapterID: UUID?
    var type: CaptureType
    var rawText: String
    var assetPath: String?
    var sourceURL: String
    var createdAt: Date
}

struct AIProvenance: Identifiable, Codable, Hashable {
    var id: UUID
    var model: String
    var purpose: String
    var inputScope: AIScope
    var linkedID: UUID?
    var createdAt: Date
}

struct AIThreadMessage: Identifiable, Codable, Hashable {
    var id: UUID
    var scope: AIScope
    var linkedID: UUID?
    var role: String
    var content: String
    var createdAt: Date
}

struct QuoteCard: Identifiable, Codable, Hashable {
    var id: UUID
    var quoteID: UUID
    var theme: String
    var format: String
    var payloadJSON: String
    var createdAt: Date
}

struct BookMetadata: Codable, Hashable {
    var title: String
    var author: String
    var isbn: String
    var summary: String
    var coverURL: URL?
    var source: String
}

struct ChapterDraft: Codable, Hashable, Identifiable {
    var id = UUID()
    var title: String
    var summary: String
    var pageStart: Int?
    var pageEnd: Int?
}

struct QuoteCandidate: Identifiable, Codable, Hashable {
    var id = UUID()
    var text: String
    var cleanedText: String
    var suggestedChapterID: UUID?
    var pageLocator: String
    var kind: CapturedContentKind
    var tags: [String]
    var note: String
    var confidence: Double
}

enum CapturedContentKind: String, Codable, CaseIterable, Identifiable {
    case quote
    case passage
    case idea
    case note
    case question
    case code

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quote: "Quote"
        case .passage: "Passage"
        case .idea: "Idea"
        case .note: "Note"
        case .question: "Question"
        case .code: "Code"
        }
    }
}

struct CandidateSource: Hashable {
    var captureID: UUID?
    var sourceType: SourceType
    var sourceURL: String
}

enum AIAttachmentKind: String, Codable, CaseIterable, Identifiable {
    case pdf
    case image
    case web
    case text

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pdf: "PDF"
        case .image: "Image"
        case .web: "Link"
        case .text: "Text"
        }
    }

    var icon: String {
        switch self {
        case .pdf: "doc.richtext"
        case .image: "photo"
        case .web: "link"
        case .text: "text.alignleft"
        }
    }
}

struct AIAttachment: Identifiable, Codable, Hashable {
    var id = UUID()
    var kind: AIAttachmentKind
    var name: String
    var extractedText: String
    var sourceURL: String
    var assetPath: String?
    var captureID: UUID?
    var createdAt: Date

    var textPreview: String {
        extractedText
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func promptDescription(maxCharacters: Int = 5000) -> String {
        let cleanText = extractedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = cleanText.isEmpty ? "No readable text extracted." : String(cleanText.prefix(maxCharacters))
        return """
        Attachment: \(name)
        Type: \(kind.title)
        Source: \(sourceURL.isEmpty ? "local capture" : sourceURL)
        Extracted text:
        \(body)
        """
    }
}

enum AIAttachmentPolicy {
    static let maxItems = 5
}

enum CaptureImportPolicy {
    static let maxFileBytes = 25 * 1024 * 1024
    static let maxWebBytes = 4 * 1024 * 1024
    static let maxPDFPages = 40
    static let maxImagePixels = 24_000_000
    static let maxExtractedCharacters = 80_000
}

extension Book {
    static let sample = Book(
        id: UUID(),
        title: "The Creative Act",
        nickname: "",
        author: "Rick Rubin",
        isbn: "",
        summary: "A working shelf for captured quotes, ideas, and context.",
        learnings: "",
        coverAssetPath: nil,
        dominantHex: "#6C7A58",
        metadataSource: "sample",
        createdAt: .now,
        updatedAt: .now
    )
}

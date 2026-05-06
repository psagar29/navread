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

extension Book {
    static let sample = Book(
        id: UUID(),
        title: "The Creative Act",
        nickname: "",
        author: "Rick Rubin",
        isbn: "",
        summary: "A working shelf for captured passages, ideas, and context.",
        coverAssetPath: nil,
        dominantHex: "#6C7A58",
        metadataSource: "sample",
        createdAt: .now,
        updatedAt: .now
    )
}

import Foundation
import Testing
@testable import NavRead

@Test func quotePrefersCleanedText() {
    let quote = Quote(
        id: UUID(),
        bookID: UUID(),
        chapterID: nil,
        rawText: " raw OCR text ",
        cleanedText: "Clean quote text.",
        pageLocator: "p. 42",
        note: "",
        tags: ["clarity"],
        sourceType: .manual,
        sourceURL: "",
        captureID: nil,
        createdAt: .now,
        updatedAt: .now
    )

    #expect(quote.text == "Clean quote text.")
}

@Test func emptyAuthorUsesFallbackLabel() {
    var book = Book.sample
    book.author = ""

    #expect(book.displayAuthor == "Unknown author")
}

@Test func onboardingShowsOnlyForFreshInstall() {
    let state = FirstRunOnboardingGate.resolve(
        hasCompleted: false,
        hasStarted: false,
        libraryExistedBeforeSetup: false
    )

    #expect(state == FirstRunOnboardingState(hasCompleted: false, hasStarted: true, shouldPresent: true))
}

@Test func onboardingDoesNotShowForExistingLibrary() {
    let state = FirstRunOnboardingGate.resolve(
        hasCompleted: false,
        hasStarted: false,
        libraryExistedBeforeSetup: true
    )

    #expect(state == FirstRunOnboardingState(hasCompleted: true, hasStarted: false, shouldPresent: false))
}

@Test func onboardingResumesAfterPartialSetup() {
    let state = FirstRunOnboardingGate.resolve(
        hasCompleted: false,
        hasStarted: true,
        libraryExistedBeforeSetup: true
    )

    #expect(state == FirstRunOnboardingState(hasCompleted: false, hasStarted: true, shouldPresent: true))
}

@Test func aiAttachmentPromptTruncatesReadableText() {
    let attachment = AIAttachment(
        kind: .pdf,
        name: "notes.pdf",
        extractedText: String(repeating: "a", count: 32),
        sourceURL: "/tmp/notes.pdf",
        assetPath: nil,
        captureID: nil,
        createdAt: .now
    )

    let prompt = attachment.promptDescription(maxCharacters: 12)

    #expect(prompt.contains("notes.pdf"))
    #expect(prompt.contains("PDF"))
    #expect(prompt.contains(String(repeating: "a", count: 12)))
    #expect(!prompt.contains(String(repeating: "a", count: 13)))
}

@Test func aiAttachmentPolicyCapsSingleTurnUploads() {
    #expect(AIAttachmentPolicy.maxItems == 5)
}

@Test func updatingBookDoesNotDeleteChildRows() throws {
    let database = try makeTemporaryDatabase()
    let now = Date()
    var book = Book.sample
    book.id = UUID()
    book.createdAt = now
    book.updatedAt = now
    let chapter = Chapter(
        id: UUID(),
        bookID: book.id,
        title: "Chapter One",
        orderIndex: 0,
        summary: "",
        learnings: "",
        pageStart: nil,
        pageEnd: nil,
        aiGenerated: false,
        createdAt: now,
        updatedAt: now
    )
    let quote = Quote(
        id: UUID(),
        bookID: book.id,
        chapterID: chapter.id,
        rawText: "Original",
        cleanedText: "Original",
        pageLocator: "",
        note: "",
        tags: [],
        sourceType: .manual,
        sourceURL: "",
        captureID: nil,
        createdAt: now,
        updatedAt: now
    )

    try database.insert(book: book)
    try database.insert(chapter: chapter)
    try database.insert(quote: quote)
    book.title = "Updated"
    book.updatedAt = now.addingTimeInterval(1)
    try database.insert(book: book)

    #expect(try database.loadChapters(bookID: book.id).count == 1)
    #expect(try database.loadQuotes(bookID: book.id).count == 1)
}

@Test func savedQuoteRoundTripsAndDeletes() throws {
    let database = try makeTemporaryDatabase()
    let quote = SavedQuote(
        id: UUID(),
        text: "Attention is the beginning of devotion.",
        author: "Mary Oliver",
        source: "online",
        note: "Standalone quote",
        tags: ["attention", "devotion"],
        createdAt: .now,
        updatedAt: .now
    )

    try database.insert(savedQuote: quote)

    let saved = try #require(database.loadSavedQuotes().first)
    #expect(saved.text == quote.text)
    #expect(saved.author == "Mary Oliver")
    #expect(saved.tags == ["attention", "devotion"])

    try database.deleteSavedQuote(quote.id)
    #expect(try database.loadSavedQuotes().isEmpty)
}

@Test func bulkSavedQuoteImportParsesAttributionAndDeduplicates() async {
    let service = NavReadAIService()
    let paste = """
    "We are what we repeatedly do. Excellence, then, is not an act, but a habit." - Aristotle
    "The impediment to action advances action. What stands in the way becomes the way." - Marcus Aurelius, Meditations
    "We are what we repeatedly do. Excellence, then, is not an act, but a habit." - Aristotle
    """

    let candidates = await service.savedQuoteCandidates(from: paste, preferCodex: false)

    #expect(candidates.count == 2)
    #expect(candidates.first?.text == "We are what we repeatedly do. Excellence, then, is not an act, but a habit.")
    #expect(candidates.first?.author == "Aristotle")
    #expect(candidates.last?.author == "Marcus Aurelius")
    #expect(candidates.last?.source == "Meditations")
}

@Test func markdownExportIncludesUnassignedQuotes() {
    let book = Book.sample
    let chapter = Chapter(
        id: UUID(),
        bookID: book.id,
        title: "Chapter One",
        orderIndex: 0,
        summary: "",
        learnings: "",
        pageStart: nil,
        pageEnd: nil,
        aiGenerated: false,
        createdAt: .now,
        updatedAt: .now
    )
    let quote = Quote(
        id: UUID(),
        bookID: book.id,
        chapterID: nil,
        rawText: "Unassigned quote",
        cleanedText: "Unassigned quote",
        pageLocator: "p. 9",
        note: "",
        tags: [],
        sourceType: .manual,
        sourceURL: "",
        captureID: nil,
        createdAt: .now,
        updatedAt: .now
    )

    let markdown = ExportService.markdown(book: book, chapters: [chapter], quotes: [quote])

    #expect(markdown.contains("## Unassigned"))
    #expect(markdown.contains("Unassigned quote"))
}

@Test func markdownExportIncludesBookLearnings() {
    var book = Book.sample
    book.learnings = "The core lesson is to build a daily creative practice."

    let markdown = ExportService.markdown(book: book, chapters: [], quotes: [])

    #expect(markdown.contains("## Book Learnings"))
    #expect(markdown.contains(book.learnings))
}

@Test func chapterLearningsRoundTripAndExport() throws {
    let database = try makeTemporaryDatabase()
    var book = Book.sample
    book.id = UUID()
    let chapter = Chapter(
        id: UUID(),
        bookID: book.id,
        title: "Attention",
        orderIndex: 0,
        summary: "A chapter about noticing.",
        learnings: "Attention compounds into taste.",
        pageStart: nil,
        pageEnd: nil,
        aiGenerated: false,
        createdAt: .now,
        updatedAt: .now
    )

    try database.insert(book: book)
    try database.insert(chapter: chapter)

    let saved = try #require(database.loadChapters(bookID: book.id).first)
    #expect(saved.learnings == chapter.learnings)

    let markdown = ExportService.markdown(book: book, chapters: [saved], quotes: [])
    #expect(markdown.contains("### Chapter Learnings"))
    #expect(markdown.contains(chapter.learnings))
}

private func makeTemporaryDatabase() throws -> SQLiteDatabase {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return try SQLiteDatabase(path: directory.appendingPathComponent("NavRead.sqlite"))
}

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

@Test func markdownExportIncludesUnassignedQuotes() {
    let book = Book.sample
    let chapter = Chapter(
        id: UUID(),
        bookID: book.id,
        title: "Chapter One",
        orderIndex: 0,
        summary: "",
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

private func makeTemporaryDatabase() throws -> SQLiteDatabase {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return try SQLiteDatabase(path: directory.appendingPathComponent("NavRead.sqlite"))
}

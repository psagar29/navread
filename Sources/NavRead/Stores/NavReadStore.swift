import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class NavReadStore: ObservableObject {
    @Published var books: [Book] = []
    @Published var allQuotes: [Quote] = []
    @Published var chapters: [Chapter] = []
    @Published var quotes: [Quote] = []
    @Published var captures: [Capture] = []
    @Published var selectedBookID: UUID?
    @Published var selectedChapterID: UUID?
    @Published var selectedQuoteID: UUID?
    @Published var searchText = ""
    @Published var isWorking = false
    @Published var statusMessage = ""
    @Published var authState = CodexAuthState()
    @Published var lastCandidateSource: CandidateSource?

    let libraryExistedBeforeSetup: Bool

    private let database: SQLiteDatabase
    private let metadataService = BookMetadataService()
    private let coverCache = CoverCache()
    private let aiService = NavReadAIService()
    private let captureService = CaptureService()
    private let oauthService = CodexOAuthService()
    private var isBackfillingCovers = false

    init() {
        do {
            libraryExistedBeforeSetup = LibraryPaths.libraryExistsBeforeSetup
            try LibraryPaths.ensure()
            database = try SQLiteDatabase(path: LibraryPaths.database)
            refresh()
            refreshAuth()
        } catch {
            fatalError("Failed to open NavRead library: \(error.localizedDescription)")
        }
    }

    var selectedBook: Book? {
        books.first { $0.id == selectedBookID } ?? books.first
    }

    var selectedChapter: Chapter? {
        chapters.first { $0.id == selectedChapterID }
    }

    var selectedQuote: Quote? {
        quotes.first { $0.id == selectedQuoteID } ?? quotes.first
    }

    var filteredBooks: [Book] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return books }
        let term = searchText.lowercased()
        return books.filter { book in
            book.title.lowercased().contains(term)
                || book.nickname.lowercased().contains(term)
                || book.author.lowercased().contains(term)
                || allQuotes.contains { $0.bookID == book.id && $0.text.lowercased().contains(term) }
                || allQuotes.contains { $0.bookID == book.id && $0.tags.contains(where: { $0.lowercased().contains(term) }) }
                || allQuotes.contains { $0.bookID == book.id && $0.note.lowercased().contains(term) }
        }
    }

    var searchQuoteMatches: [Quote] {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !term.isEmpty else { return [] }
        return allQuotes.filter { quote in
            quote.text.lowercased().contains(term)
                || quote.tags.contains { $0.lowercased().contains(term) }
                || quote.note.lowercased().contains(term)
                || bookTitle(for: quote.bookID).lowercased().contains(term)
        }
    }

    var totalQuoteCount: Int {
        allQuotes.count
    }

    func refresh() {
        do {
            books = try database.loadBooks()
            allQuotes = try database.loadAllQuotes()
            if selectedBookID == nil || books.contains(where: { $0.id == selectedBookID }) == false {
                selectedBookID = books.first?.id
            }
            loadSelectedBookCollections()
            backfillMissingCoversIfNeeded()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func selectBook(_ book: Book) {
        withAnimation(.snappy(duration: 0.28)) {
            selectedBookID = book.id
            selectedQuoteID = nil
        }
        loadSelectedBookCollections()
    }

    func selectChapter(_ chapter: Chapter) {
        withAnimation(.snappy(duration: 0.24)) {
            selectedChapterID = chapter.id
            selectedQuoteID = quotes.first { $0.chapterID == chapter.id }?.id
        }
    }

    func selectQuote(_ quote: Quote) {
        if selectedBookID != quote.bookID {
            selectedBookID = quote.bookID
            loadSelectedBookCollections()
        }
        selectedChapterID = quote.chapterID
        selectedQuoteID = quote.id
    }

    func bookTitle(for id: UUID) -> String {
        books.first { $0.id == id }?.title ?? "Unknown book"
    }

    func addBook(title: String, author: String, isbn: String) async {
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTitle.isEmpty else { return }
        isWorking = true
        statusMessage = "Resolving book metadata..."
        defer { isWorking = false }

        let metadata = await metadataService.resolve(title: cleanedTitle, author: author, isbn: isbn)
        statusMessage = "Caching cover..."
        let cover = await coverCache.cacheCover(from: metadata.coverURL, title: metadata.title, author: metadata.author)
        statusMessage = "Drafting chapters..."
        let authenticated = TokenVault.shared.load() != nil
        let drafts = await aiService.chapterDrafts(for: metadata, authenticated: authenticated)
        let now = Date()
        let book = Book(
            id: UUID(),
            title: metadata.title,
            nickname: "",
            author: metadata.author,
            isbn: metadata.isbn,
            summary: metadata.summary,
            coverAssetPath: cover.path,
            dominantHex: cover.dominantHex,
            metadataSource: metadata.source,
            createdAt: now,
            updatedAt: now
        )
        do {
            try database.insert(book: book)
            for (index, draft) in drafts.enumerated() {
                try database.insert(
                    chapter: Chapter(
                        id: UUID(),
                        bookID: book.id,
                        title: draft.title,
                        orderIndex: index,
                        summary: draft.summary,
                        pageStart: draft.pageStart,
                        pageEnd: draft.pageEnd,
                        aiGenerated: true,
                        createdAt: now,
                        updatedAt: now
                    )
                )
            }
            try database.insert(
                provenance: AIProvenance(
                    id: UUID(),
                    model: authenticated ? "gpt-5.4" : "offline-scaffold",
                    purpose: "chapter_scaffold",
                    inputScope: .book,
                    linkedID: book.id,
                    createdAt: now
                )
            )
            selectedBookID = book.id
            refresh()
            statusMessage = "Added \(book.title)."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func updateBook(_ book: Book, title: String, nickname: String, author: String, summary: String) {
        var updated = book
        updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.nickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.author = author.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.updatedAt = Date()
        guard !updated.title.isEmpty else { return }

        do {
            try database.insert(book: updated)
            selectedBookID = updated.id
            refresh()
            statusMessage = "Updated \(updated.displayTitle)."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func addManualQuote(rawText: String, cleanedText: String, pageLocator: String, note: String, tags: [String]) {
        guard let book = selectedBook else { return }
        let now = Date()
        let quote = Quote(
            id: UUID(),
            bookID: book.id,
            chapterID: selectedChapterID ?? chapters.first?.id,
            rawText: rawText,
            cleanedText: cleanedText,
            pageLocator: pageLocator,
            note: note,
            tags: tags.normalizedTags(),
            sourceType: .manual,
            sourceURL: "",
            captureID: nil,
            createdAt: now,
            updatedAt: now
        )
        do {
            try database.insert(quote: quote)
            selectedQuoteID = quote.id
            loadSelectedBookCollections()
            allQuotes = try database.loadAllQuotes()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func updateQuote(_ quote: Quote, cleanedText: String, pageLocator: String, note: String, tags: [String]) {
        var updated = quote
        updated.cleanedText = cleanedText
        updated.pageLocator = pageLocator
        updated.note = note
        updated.tags = tags.normalizedTags()
        updated.updatedAt = Date()
        do {
            try database.insert(quote: updated)
            selectedQuoteID = quote.id
            loadSelectedBookCollections()
            allQuotes = try database.loadAllQuotes()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func deleteSelectedQuote() {
        guard let quote = selectedQuote else { return }
        do {
            try database.deleteQuote(quote.id)
            selectedQuoteID = nil
            loadSelectedBookCollections()
            allQuotes = try database.loadAllQuotes()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func deleteBook(_ book: Book) {
        do {
            let capturePaths = try database.loadCaptures(bookID: book.id).compactMap(\.assetPath)
            try database.deleteBook(book.id)
            deleteLocalAsset(path: book.coverAssetPath)
            for path in capturePaths {
                deleteLocalAsset(path: path)
            }
            if selectedBookID == book.id {
                selectedBookID = nil
                selectedChapterID = nil
                selectedQuoteID = nil
            }
            refresh()
            statusMessage = "Deleted \(book.displayTitle)."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func addChapter() {
        guard let book = selectedBook else { return }
        let nextIndex = (chapters.map(\.orderIndex).max() ?? -1) + 1
        let now = Date()
        let chapter = Chapter(
            id: UUID(),
            bookID: book.id,
            title: "New Chapter",
            orderIndex: nextIndex,
            summary: "User-created chapter.",
            pageStart: nil,
            pageEnd: nil,
            aiGenerated: false,
            createdAt: now,
            updatedAt: now
        )
        do {
            try database.insert(chapter: chapter)
            selectedChapterID = chapter.id
            loadSelectedBookCollections()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func updateChapter(_ chapter: Chapter, title: String, summary: String, pageStart: Int?, pageEnd: Int?) {
        var updated = chapter
        updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.pageStart = pageStart
        updated.pageEnd = pageEnd
        updated.aiGenerated = false
        updated.updatedAt = Date()
        guard !updated.title.isEmpty else { return }
        do {
            try database.insert(chapter: updated)
            selectedChapterID = updated.id
            loadSelectedBookCollections()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func deleteSelectedChapter() {
        guard let chapter = selectedChapter, chapters.count > 1 else { return }
        do {
            try database.deleteChapter(chapter.id)
            selectedChapterID = nil
            loadSelectedBookCollections()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func extractManualCapture(_ rawText: String) async -> [QuoteCandidate] {
        guard let book = selectedBook else { return [] }
        let cleaned = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return [] }
        isWorking = true
        defer { isWorking = false }
        let capture = Capture(
            id: UUID(),
            bookID: book.id,
            chapterID: selectedChapterID,
            type: .manualText,
            rawText: cleaned,
            assetPath: nil,
            sourceURL: "",
            createdAt: .now
        )
        do {
            try database.insert(capture: capture)
            lastCandidateSource = CandidateSource(captureID: capture.id, sourceType: .clipboard, sourceURL: "")
            loadSelectedBookCollections()
            return await aiService.quoteCandidates(from: cleaned, chapters: chapters)
        } catch {
            statusMessage = error.localizedDescription
            return []
        }
    }

    func importFileCapture(_ url: URL) async -> [QuoteCandidate] {
        guard let book = selectedBook else { return [] }
        isWorking = true
        defer { isWorking = false }
        do {
            let extracted = try await captureService.extractText(from: url)
            let capture = Capture(
                id: UUID(),
                bookID: book.id,
                chapterID: selectedChapterID,
                type: extracted.type,
                rawText: extracted.text,
                assetPath: extracted.assetPath,
                sourceURL: url.path,
                createdAt: .now
            )
            try database.insert(capture: capture)
            lastCandidateSource = CandidateSource(
                captureID: capture.id,
                sourceType: extracted.type == .pdfPage ? .pdf : .image,
                sourceURL: url.path
            )
            loadSelectedBookCollections()
            return await aiService.quoteCandidates(from: extracted.text, chapters: chapters)
        } catch {
            statusMessage = error.localizedDescription
            return []
        }
    }

    func importWebCapture(_ rawURL: String) async -> [QuoteCandidate] {
        guard let book = selectedBook else { return [] }
        isWorking = true
        defer { isWorking = false }
        do {
            let text = try await captureService.extractWebText(from: rawURL)
            let capture = Capture(
                id: UUID(),
                bookID: book.id,
                chapterID: selectedChapterID,
                type: .webURL,
                rawText: text,
                assetPath: nil,
                sourceURL: rawURL,
                createdAt: .now
            )
            try database.insert(capture: capture)
            lastCandidateSource = CandidateSource(captureID: capture.id, sourceType: .web, sourceURL: rawURL)
            loadSelectedBookCollections()
            return await aiService.quoteCandidates(from: text, chapters: chapters)
        } catch {
            statusMessage = error.localizedDescription
            return []
        }
    }

    func acceptCandidate(_ candidate: QuoteCandidate, sourceType: SourceType = .manual) {
        guard let book = selectedBook else { return }
        let now = Date()
        let source = lastCandidateSource
        let quote = Quote(
            id: UUID(),
            bookID: book.id,
            chapterID: candidate.suggestedChapterID ?? selectedChapterID ?? chapters.first?.id,
            rawText: candidate.text,
            cleanedText: candidate.cleanedText,
            pageLocator: candidate.pageLocator,
            note: candidate.note,
            tags: (candidate.tags + ["type-\(candidate.kind.rawValue)"]).normalizedTags(),
            sourceType: source?.sourceType ?? sourceType,
            sourceURL: source?.sourceURL ?? "",
            captureID: source?.captureID,
            createdAt: now,
            updatedAt: now
        )
        do {
            try database.insert(quote: quote)
            selectedQuoteID = quote.id
            loadSelectedBookCollections()
            allQuotes = try database.loadAllQuotes()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func askAI(_ prompt: String) async -> String {
        guard let book = selectedBook else { return "Add a book first." }
        if TokenVault.shared.load() == nil {
            return "Codex is not connected. Sign in to use model-authored replies. Local context: \(book.title), \(chapters.count) chapters, \(quotes.count) quotes."
        }
        return await aiService.chatReply(prompt: prompt, context: aiContextDescription())
    }

    func askAIStream(_ prompt: String, conversationHistory: String = "") -> AsyncThrowingStream<String, Error> {
        guard let book = selectedBook else {
            return AsyncThrowingStream { continuation in
                continuation.yield("Add a book first.")
                continuation.finish()
            }
        }
        guard TokenVault.shared.load() != nil else {
            return AsyncThrowingStream { continuation in
                continuation.yield("Codex is not connected. Sign in from Settings to use model-authored replies. Local context: \(book.title), \(chapters.count) chapters, \(quotes.count) quotes.")
                continuation.finish()
            }
        }
        return aiService.chatReplyStream(
            prompt: prompt,
            context: aiContextDescription(),
            conversationHistory: conversationHistory
        )
    }

    func startCodexLogin() async {
        authState.pending = true
        authState.statusMessage = "Listening on localhost:1455..."
        do {
            let url = try await oauthService.startLogin()
            authState.statusMessage = "Opening Codex sign-in..."
            NSWorkspace.shared.open(url)
        } catch {
            authState.pending = false
            authState.statusMessage = error.localizedDescription
        }
    }

    func completeCodexCallback(_ value: String) async {
        do {
            let credentials = try await oauthService.completeManualCallback(value)
            authState.authenticated = true
            authState.pending = false
            authState.accountID = credentials.accountID
            authState.statusMessage = "Codex connected"
        } catch {
            authState.statusMessage = error.localizedDescription
        }
    }

    func codexCallbackCompleted(accountID: String) {
        authState.authenticated = true
        authState.pending = false
        authState.accountID = accountID
        authState.statusMessage = accountID.isEmpty ? "Codex connected" : "Codex connected: \(accountID)"
    }

    func codexCallbackFailed(message: String) {
        authState.authenticated = false
        authState.pending = false
        authState.statusMessage = message
    }

    func signOutCodex() {
        TokenVault.shared.clear()
        refreshAuth()
    }

    func exportMarkdown() -> String {
        guard let book = selectedBook else { return "" }
        return ExportService.markdown(book: book, chapters: chapters, quotes: quotes)
    }

    func exportJSON() -> String {
        guard let book = selectedBook else { return "" }
        return ExportService.json(book: book, chapters: chapters, quotes: quotes, captures: captures)
    }

    func exportCSV() -> String {
        guard let book = selectedBook else { return "" }
        return ExportService.csv(book: book, chapters: chapters, quotes: quotes)
    }

    func copyExport(_ format: ExportFormat) {
        let payload: String
        switch format {
        case .markdown:
            payload = exportMarkdown()
        case .json:
            payload = exportJSON()
        case .csv:
            payload = exportCSV()
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(payload, forType: .string)
        statusMessage = "\(format.rawValue.uppercased()) export copied."
    }

    func saveExport(_ format: ExportFormat) {
        guard let book = selectedBook else { return }
        let payload = exportPayload(format)
        let panel = NSSavePanel()
        panel.title = "Export \(book.title)"
        panel.nameFieldStringValue = "\(safeFilename(book.title)).\(format.fileExtension)"
        panel.allowedContentTypes = [format.contentType]
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try payload.write(to: url, atomically: true, encoding: .utf8)
                statusMessage = "Saved \(format.rawValue.uppercased()) export."
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    func addCurrentBookToNotes() {
        guard let book = selectedBook else { return }
        let html = ExportService.htmlNote(book: book, chapters: chapters, quotes: quotes)
        let script = """
        tell application "Notes"
          activate
          make new note at folder "Notes" of default account with properties {name:"\(appleScriptEscaped("NavRead - \(book.title)") )", body:"\(appleScriptEscaped(html))"}
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if error == nil {
            statusMessage = "Added \(book.title) to Notes."
            return
        }

        let notesServiceName = NSSharingService.Name(rawValue: "com.apple.Notes.SharingExtension")
        guard let service = NSSharingService(named: notesServiceName) else {
            copyExport(.markdown)
            statusMessage = "Notes sharing is unavailable. Markdown export copied."
            return
        }
        service.subject = "NavRead - \(book.title)"
        service.perform(withItems: [exportMarkdown()])
        statusMessage = "Sent \(book.title) to Notes."
    }

    func openLibraryFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([LibraryPaths.root])
    }

    func backfillMissingCoversIfNeeded() {
        guard !isBackfillingCovers else { return }
        let targets = books.filter { book in
            guard let path = book.coverAssetPath, !path.isEmpty else { return true }
            return FileManager.default.fileExists(atPath: path) == false
        }
        guard !targets.isEmpty else { return }

        isBackfillingCovers = true
        Task {
            var updatedCount = 0
            for book in targets {
                let metadata = await metadataService.resolve(title: book.title, author: book.author, isbn: book.isbn)
                let cover = await coverCache.cacheCover(from: metadata.coverURL, title: book.title, author: book.author)
                guard let path = cover.path else { continue }
                var updated = book
                updated.coverAssetPath = path
                updated.dominantHex = cover.dominantHex
                do {
                    try database.insert(book: updated)
                    updatedCount += 1
                } catch {
                    statusMessage = error.localizedDescription
                    break
                }
            }
            isBackfillingCovers = false
            if updatedCount > 0 {
                refresh()
                statusMessage = "Cached \(updatedCount) book covers."
            }
        }
    }


    private func exportPayload(_ format: ExportFormat) -> String {
        switch format {
        case .markdown: exportMarkdown()
        case .json: exportJSON()
        case .csv: exportCSV()
        }
    }

    private func loadSelectedBookCollections() {
        guard let bookID = selectedBookID else {
            chapters = []
            quotes = []
            captures = []
            allQuotes = (try? database.loadAllQuotes()) ?? []
            return
        }
        do {
            chapters = try database.loadChapters(bookID: bookID)
            quotes = try database.loadQuotes(bookID: bookID)
            captures = try database.loadCaptures(bookID: bookID)
            allQuotes = try database.loadAllQuotes()
            if selectedChapterID == nil || chapters.contains(where: { $0.id == selectedChapterID }) == false {
                selectedChapterID = chapters.first?.id
            }
            if selectedQuoteID == nil || quotes.contains(where: { $0.id == selectedQuoteID }) == false {
                selectedQuoteID = quotes.first?.id
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func refreshAuth() {
        if let credentials = TokenVault.shared.load(), credentials.expiresAt > .now {
            authState.authenticated = true
            authState.pending = false
            authState.accountID = credentials.accountID
            authState.statusMessage = "Codex connected"
        } else {
            authState.authenticated = false
            authState.accountID = ""
            authState.statusMessage = "Codex not connected"
        }
    }

    private func safeFilename(_ value: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return value.components(separatedBy: illegal).joined(separator: "-")
    }

    private func aiContextDescription() -> String {
        guard let book = selectedBook else { return "No selected book." }
        let chapterMap = chapters.enumerated().map { index, chapter in
            let pages: String
            switch (chapter.pageStart, chapter.pageEnd) {
            case let (.some(start), .some(end)):
                pages = " pages \(start)-\(end)"
            case let (.some(start), .none):
                pages = " page \(start)"
            default:
                pages = ""
            }
            return "\(index + 1). \(chapter.title)\(pages): \(chapter.summary)"
        }.joined(separator: "\n")

        let quoteMap = quotes.prefix(16).enumerated().map { index, quote in
            let chapterTitle = chapters.first { $0.id == quote.chapterID }?.title ?? "Unassigned"
            let tagList = quote.tags.isEmpty ? "" : " tags: \(quote.tags.joined(separator: ", "))"
            let locator = quote.pageLocator.isEmpty ? "" : " page/location: \(quote.pageLocator)"
            return "\(index + 1). [\(chapterTitle)] \(quote.text)\(locator)\(tagList)"
        }.joined(separator: "\n")

        let captureMap = captures.prefix(8).enumerated().map { index, capture in
            let chapterTitle = chapters.first { $0.id == capture.chapterID }?.title ?? "Unassigned"
            let preview = capture.rawText.replacingOccurrences(of: "\n", with: " ").prefix(420)
            return "\(index + 1). \(capture.type.rawValue) [\(chapterTitle)]: \(preview)"
        }.joined(separator: "\n")

        let selectedChapterText = selectedChapter.map { chapter in
            "Current chapter: \(chapter.title)\nSummary: \(chapter.summary)"
        } ?? "Current chapter: none selected."

        let selectedQuoteText = selectedQuote.map { quote in
            """
            Selected quote:
            \(quote.text)
            Note: \(quote.note.isEmpty ? "None" : quote.note)
            Tags: \(quote.tags.isEmpty ? "None" : quote.tags.joined(separator: ", "))
            """
        } ?? "Selected quote: none selected."

        return """
        Book:
        Title: \(book.title)
        Display title: \(book.displayTitle)
        Author: \(book.displayAuthor)
        ISBN: \(book.isbn.isEmpty ? "None" : book.isbn)
        Summary: \(book.summary.isEmpty ? "None" : book.summary)

        \(selectedChapterText)

        \(selectedQuoteText)

        Chapter map:
        \(chapterMap.isEmpty ? "No chapters yet." : chapterMap)

        Saved quotes:
        \(quoteMap.isEmpty ? "No saved quotes yet." : quoteMap)

        Recent captures:
        \(captureMap.isEmpty ? "No captures yet." : captureMap)
        """
    }

    private func appleScriptEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private func deleteLocalAsset(path: String?) {
        guard let path, !path.isEmpty else { return }
        let url = URL(fileURLWithPath: path)
        guard url.path.hasPrefix(LibraryPaths.assets.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

extension [String] {
    func normalizedTags() -> [String] {
        Array(Set(map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: " ", with: "-") }
            .filter { !$0.isEmpty }))
            .sorted()
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

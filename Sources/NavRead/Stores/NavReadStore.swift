import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class NavReadStore: ObservableObject {
    @Published var books: [Book] = []
    @Published var allQuotes: [Quote] = []
    @Published var savedQuotes: [SavedQuote] = []
    @Published var allCaptures: [Capture] = []
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
                || book.summary.lowercased().contains(term)
                || book.learnings.lowercased().contains(term)
                || allQuotes.contains { $0.bookID == book.id && $0.text.lowercased().contains(term) }
                || allQuotes.contains { $0.bookID == book.id && $0.tags.contains(where: { $0.lowercased().contains(term) }) }
                || allQuotes.contains { $0.bookID == book.id && $0.note.lowercased().contains(term) }
                || allCaptures.contains {
                    $0.bookID == book.id
                        && ($0.rawText.lowercased().contains(term) || $0.sourceURL.lowercased().contains(term))
                }
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

    var searchSavedQuoteMatches: [SavedQuote] {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !term.isEmpty else { return [] }
        return savedQuotes.filter { quote in
            quote.text.lowercased().contains(term)
                || quote.author.lowercased().contains(term)
                || quote.source.lowercased().contains(term)
                || quote.note.lowercased().contains(term)
                || quote.tags.contains { $0.lowercased().contains(term) }
        }
    }

    var totalQuoteCount: Int {
        allQuotes.count + savedQuotes.count
    }

    func refresh() {
        do {
            books = try database.loadBooks()
            allQuotes = try database.loadAllQuotes()
            savedQuotes = try database.loadSavedQuotes()
            allCaptures = try database.loadAllCaptures()
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
            learnings: "",
            coverAssetPath: cover.path,
            dominantHex: cover.dominantHex,
            metadataSource: metadata.source,
            createdAt: now,
            updatedAt: now
        )
        do {
            do {
                try database.transaction {
                    try database.insert(book: book)
                    for (index, draft) in drafts.enumerated() {
                        try database.insert(
                            chapter: Chapter(
                                id: UUID(),
                                bookID: book.id,
                                title: draft.title,
                                orderIndex: index,
                                summary: draft.summary,
                                learnings: "",
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
                }
            } catch {
                deleteLocalAsset(path: cover.path)
                throw error
            }
            selectedBookID = book.id
            refresh()
            statusMessage = "Added \(book.title)."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func updateBook(_ book: Book, title: String, nickname: String, author: String, summary: String, learnings: String? = nil) {
        var updated = book
        updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.nickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.author = author.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if let learnings {
            updated.learnings = learnings.trimmingCharacters(in: .whitespacesAndNewlines)
        }
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

    func updateBookLearnings(_ book: Book, learnings: String) {
        var updated = book
        updated.learnings = learnings.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.updatedAt = Date()
        do {
            try database.insert(book: updated)
            selectedBookID = updated.id
            refresh()
            statusMessage = "Saved book learnings."
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
            deleteQuoteCardAssets(for: quote.id)
            selectedQuoteID = nil
            loadSelectedBookCollections()
            allQuotes = try database.loadAllQuotes()
            allCaptures = try database.loadAllCaptures()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func addSavedQuote(text: String, author: String, source: String, note: String, tags: [String]) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        let now = Date()
        let quote = SavedQuote(
            id: UUID(),
            text: cleaned,
            author: author.trimmingCharacters(in: .whitespacesAndNewlines),
            source: source.trimmingCharacters(in: .whitespacesAndNewlines),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            tags: tags.normalizedTags(),
            createdAt: now,
            updatedAt: now
        )
        do {
            try database.insert(savedQuote: quote)
            savedQuotes = try database.loadSavedQuotes()
            statusMessage = "Saved quote."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func updateSavedQuote(_ quote: SavedQuote, text: String, author: String, source: String, note: String, tags: [String]) {
        var updated = quote
        updated.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.author = author.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.source = source.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.tags = tags.normalizedTags()
        updated.updatedAt = Date()
        guard !updated.text.isEmpty else { return }
        do {
            try database.insert(savedQuote: updated)
            savedQuotes = try database.loadSavedQuotes()
            statusMessage = "Updated quote."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func deleteSavedQuote(_ quote: SavedQuote) {
        do {
            try database.deleteSavedQuote(quote.id)
            deleteSavedQuoteCardAssets(for: quote.id)
            savedQuotes = try database.loadSavedQuotes()
            statusMessage = "Deleted quote."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func importSavedQuoteCandidates(_ rawText: String) async -> [SavedQuoteCandidate] {
        let cleaned = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return [] }
        isWorking = true
        statusMessage = TokenVault.shared.load() == nil ? "Parsing quotes locally..." : "Asking Codex to parse quotes..."
        defer { isWorking = false }
        let candidates = await aiService.savedQuoteCandidates(from: cleaned)
        statusMessage = candidates.isEmpty ? "No quote candidates found." : "Found \(candidates.count) quote candidates."
        return candidates
    }

    @discardableResult
    func saveSavedQuoteCandidates(_ candidates: [SavedQuoteCandidate]) -> Int {
        let cleanedCandidates = candidates.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !cleanedCandidates.isEmpty else { return 0 }
        let now = Date()
        do {
            try database.transaction {
                for candidate in cleanedCandidates {
                    try database.insert(
                        savedQuote: SavedQuote(
                            id: UUID(),
                            text: candidate.text.trimmingCharacters(in: .whitespacesAndNewlines),
                            author: candidate.author.trimmingCharacters(in: .whitespacesAndNewlines),
                            source: candidate.source.trimmingCharacters(in: .whitespacesAndNewlines),
                            note: candidate.note.trimmingCharacters(in: .whitespacesAndNewlines),
                            tags: candidate.tags.normalizedTags(),
                            createdAt: now,
                            updatedAt: now
                        )
                    )
                }
            }
            savedQuotes = try database.loadSavedQuotes()
            statusMessage = "Saved \(cleanedCandidates.count) quotes."
            return cleanedCandidates.count
        } catch {
            statusMessage = error.localizedDescription
            return 0
        }
    }

    func deleteBook(_ book: Book) {
        do {
            let capturePaths = try database.loadCaptures(bookID: book.id).compactMap(\.assetPath)
            let quoteIDs = try database.loadQuotes(bookID: book.id).map(\.id)
            try database.deleteBook(book.id)
            deleteLocalAsset(path: book.coverAssetPath)
            for path in capturePaths {
                deleteLocalAsset(path: path)
            }
            for quoteID in quoteIDs {
                deleteQuoteCardAssets(for: quoteID)
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
            learnings: "",
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

    func updateChapterLearnings(_ chapter: Chapter, learnings: String) {
        var updated = chapter
        updated.learnings = learnings.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.updatedAt = Date()
        do {
            try database.insert(chapter: updated)
            selectedChapterID = updated.id
            loadSelectedBookCollections()
            statusMessage = "Saved chapter learnings."
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
            allCaptures = try database.loadAllCaptures()
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
            do {
                try database.insert(capture: capture)
            } catch {
                deleteLocalAsset(path: extracted.assetPath)
                throw error
            }
            lastCandidateSource = CandidateSource(
                captureID: capture.id,
                sourceType: sourceType(for: extracted.type),
                sourceURL: url.path
            )
            loadSelectedBookCollections()
            allCaptures = try database.loadAllCaptures()
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
            allCaptures = try database.loadAllCaptures()
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
        guard selectedBook != nil || !savedQuotes.isEmpty else { return "Add a book or save a standalone quote first." }
        if TokenVault.shared.load() == nil {
            let title = selectedBook?.title ?? "Quotes"
            return "Codex is not connected. Sign in to use model-authored replies. Local context: \(title), \(chapters.count) chapters, \(quotes.count) book quotes, \(savedQuotes.count) standalone quotes."
        }
        return await aiService.chatReply(prompt: prompt, context: aiContextDescription())
    }

    func askAIStream(
        _ prompt: String,
        conversationHistory: String = "",
        attachments: [AIAttachment] = []
    ) -> AsyncThrowingStream<String, Error> {
        guard selectedBook != nil || !savedQuotes.isEmpty else {
            return AsyncThrowingStream { continuation in
                continuation.yield("Add a book or save a standalone quote first.")
                continuation.finish()
            }
        }
        guard TokenVault.shared.load() != nil else {
            return AsyncThrowingStream { continuation in
                let title = selectedBook?.title ?? "Quotes"
                continuation.yield("Codex is not connected. Sign in from Settings to use model-authored replies. Local context: \(title), \(chapters.count) chapters, \(quotes.count) book quotes, \(savedQuotes.count) standalone quotes.")
                continuation.finish()
            }
        }
        let context = aiContextDescription(attachments: attachments)
        return aiService.chatReplyStream(
            prompt: prompt,
            context: context,
            conversationHistory: conversationHistory
        )
    }

    func importAIAttachmentFile(_ url: URL) async throws -> AIAttachment {
        guard let book = selectedBook else {
            throw AIError.message("Add a book before attaching files.")
        }
        isWorking = true
        defer { isWorking = false }
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
        do {
            try database.insert(capture: capture)
        } catch {
            deleteLocalAsset(path: extracted.assetPath)
            throw error
        }
        loadSelectedBookCollections()
        allCaptures = try database.loadAllCaptures()

        return AIAttachment(
            kind: attachmentKind(for: extracted.type),
            name: url.lastPathComponent,
            extractedText: extracted.text,
            sourceURL: url.path,
            assetPath: extracted.assetPath,
            captureID: capture.id,
            createdAt: capture.createdAt
        )
    }

    func importAIAttachmentLink(_ rawURL: String) async throws -> AIAttachment {
        guard let book = selectedBook else {
            throw AIError.message("Add a book before attaching links.")
        }
        let cleanedURL = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedURL.isEmpty else {
            throw AIError.message("Enter a link first.")
        }
        isWorking = true
        defer { isWorking = false }
        let text = try await captureService.extractWebText(from: cleanedURL)
        let capture = Capture(
            id: UUID(),
            bookID: book.id,
            chapterID: selectedChapterID,
            type: .webURL,
            rawText: text,
            assetPath: nil,
            sourceURL: cleanedURL,
            createdAt: .now
        )
        try database.insert(capture: capture)
        loadSelectedBookCollections()
        allCaptures = try database.loadAllCaptures()

        return AIAttachment(
            kind: .web,
            name: URL(string: cleanedURL)?.host() ?? "Web Link",
            extractedText: text,
            sourceURL: cleanedURL,
            assetPath: nil,
            captureID: capture.id,
            createdAt: capture.createdAt
        )
    }

    func importAIAttachmentText(_ text: String, name: String = "Dropped Text") async throws -> AIAttachment {
        guard let book = selectedBook else {
            throw AIError.message("Add a book before attaching text.")
        }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            throw AIError.message("Dropped text was empty.")
        }
        let boundedText = String(cleaned.prefix(CaptureImportPolicy.maxExtractedCharacters))
        let capture = Capture(
            id: UUID(),
            bookID: book.id,
            chapterID: selectedChapterID,
            type: .manualText,
            rawText: boundedText,
            assetPath: nil,
            sourceURL: "",
            createdAt: .now
        )
        try database.insert(capture: capture)
        loadSelectedBookCollections()
        allCaptures = try database.loadAllCaptures()

        return AIAttachment(
            kind: .text,
            name: name,
            extractedText: boundedText,
            sourceURL: "",
            assetPath: nil,
            captureID: capture.id,
            createdAt: capture.createdAt
        )
    }

    func startCodexLogin() async {
        guard !authState.pending else { return }
        authState.pending = true
        authState.statusMessage = "Listening on localhost:1455..."
        do {
            let url = try await oauthService.startLogin()
            authState.statusMessage = "Opening Codex sign-in..."
            NSWorkspace.shared.open(url)
        } catch {
            authState.authenticated = false
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
            authState.authenticated = false
            authState.pending = false
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

    func copySelectedQuoteCard(format: QuoteCardFormat = .square) {
        guard let quote = selectedQuote, let book = selectedBook else { return }
        guard let url = QuoteCardRenderer.render(quote: quote, book: book, format: format) else {
            statusMessage = "Could not render quote card."
            return
        }
        copyQuoteCardToPasteboard(url: url, quote: quote, book: book)
        statusMessage = "Quote card copied."
    }

    func saveSelectedQuoteCard(format: QuoteCardFormat = .square) {
        guard let quote = selectedQuote, let book = selectedBook else { return }
        guard let rendered = QuoteCardRenderer.render(quote: quote, book: book, format: format) else {
            statusMessage = "Could not render quote card."
            return
        }
        let panel = NSSavePanel()
        panel.title = "Save Quote Card"
        panel.nameFieldStringValue = "\(safeFilename(book.displayTitle))-quote-card.png"
        panel.allowedContentTypes = [.png]
        if panel.runModal() == .OK, let destination = panel.url {
            do {
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.copyItem(at: rendered, to: destination)
                statusMessage = "Quote card saved."
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    func shareSelectedQuoteCard(destination: SocialShareDestination = .system, format: QuoteCardFormat = .square) {
        guard let quote = selectedQuote, let book = selectedBook else { return }
        let quoteText = socialShareText(quote: quote, book: book)
        guard let rendered = QuoteCardRenderer.render(quote: quote, book: book, format: format) else {
            statusMessage = "Could not render quote card."
            return
        }

        switch destination {
        case .system:
            let picker = NSSharingServicePicker(items: [rendered, quoteText])
            picker.show(relativeTo: .zero, of: NSApp.keyWindow?.contentView ?? NSView(), preferredEdge: .minY)
            statusMessage = "Opened share sheet."
        case .x:
            copyQuoteCardToPasteboard(url: rendered, quote: quote, book: book)
            openShareURL("https://twitter.com/intent/tweet?text=\(urlEncoded(quoteText))")
            statusMessage = "Quote card copied. Opened X composer."
        case .whatsapp:
            copyQuoteCardToPasteboard(url: rendered, quote: quote, book: book)
            openShareURL("https://wa.me/?text=\(urlEncoded(quoteText))")
            statusMessage = "Quote card copied. Opened WhatsApp share."
        case .instagram:
            copyQuoteCardToPasteboard(url: rendered, quote: quote, book: book)
            openShareURL("https://www.instagram.com/")
            statusMessage = "Quote card copied. Paste it into Instagram."
        case .youtube:
            copyQuoteCardToPasteboard(url: rendered, quote: quote, book: book)
            openShareURL("https://www.youtube.com/")
            statusMessage = "Quote card copied. Paste it into YouTube Studio or Community."
        case .messages:
            if let service = NSSharingService(named: .composeMessage) {
                service.subject = "NavRead quote"
                service.perform(withItems: [rendered, quoteText])
                statusMessage = "Opened Messages share."
            } else {
                shareSelectedQuoteCard(destination: .system, format: format)
            }
        }
    }

    func copySavedQuoteCard(_ quote: SavedQuote, format: QuoteCardFormat = .square) {
        guard let rendered = QuoteCardRenderer.render(savedQuote: quote, format: format) else {
            statusMessage = "Could not render card."
            return
        }
        copySavedQuoteCardToPasteboard(url: rendered, quote: quote)
        statusMessage = "Quote card copied."
    }

    func saveSavedQuoteCard(_ quote: SavedQuote, format: QuoteCardFormat = .square) {
        guard let rendered = QuoteCardRenderer.render(savedQuote: quote, format: format) else {
            statusMessage = "Could not render card."
            return
        }
        let panel = NSSavePanel()
        panel.title = "Save Quote Card"
        panel.nameFieldStringValue = "\(safeFilename(quote.author.isEmpty ? "NavRead-quote" : quote.author))-card.png"
        panel.allowedContentTypes = [.png]
        if panel.runModal() == .OK, let destination = panel.url {
            do {
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.copyItem(at: rendered, to: destination)
                statusMessage = "Quote card saved."
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    func shareSavedQuoteCard(_ quote: SavedQuote, destination: SocialShareDestination = .system, format: QuoteCardFormat = .square) {
        let shareText = socialShareText(savedQuote: quote)
        guard let rendered = QuoteCardRenderer.render(savedQuote: quote, format: format) else {
            statusMessage = "Could not render card."
            return
        }

        switch destination {
        case .system:
            let picker = NSSharingServicePicker(items: [rendered, shareText])
            picker.show(relativeTo: .zero, of: NSApp.keyWindow?.contentView ?? NSView(), preferredEdge: .minY)
            statusMessage = "Opened share sheet."
        case .x:
            copySavedQuoteCardToPasteboard(url: rendered, quote: quote)
            openShareURL("https://twitter.com/intent/tweet?text=\(urlEncoded(shareText))")
            statusMessage = "Card copied. Opened X composer."
        case .whatsapp:
            copySavedQuoteCardToPasteboard(url: rendered, quote: quote)
            openShareURL("https://wa.me/?text=\(urlEncoded(shareText))")
            statusMessage = "Card copied. Opened WhatsApp share."
        case .instagram:
            copySavedQuoteCardToPasteboard(url: rendered, quote: quote)
            openShareURL("https://www.instagram.com/")
            statusMessage = "Card copied. Paste it into Instagram."
        case .youtube:
            copySavedQuoteCardToPasteboard(url: rendered, quote: quote)
            openShareURL("https://www.youtube.com/")
            statusMessage = "Card copied. Paste it into YouTube Studio or Community."
        case .messages:
            if let service = NSSharingService(named: .composeMessage) {
                service.subject = "NavRead quote"
                service.perform(withItems: [rendered, shareText])
                statusMessage = "Opened Messages share."
            } else {
                shareSavedQuoteCard(quote, destination: .system, format: format)
            }
        }
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
            savedQuotes = (try? database.loadSavedQuotes()) ?? []
            allCaptures = (try? database.loadAllCaptures()) ?? []
            return
        }
        do {
            chapters = try database.loadChapters(bookID: bookID)
            quotes = try database.loadQuotes(bookID: bookID)
            captures = try database.loadCaptures(bookID: bookID)
            allQuotes = try database.loadAllQuotes()
            savedQuotes = try database.loadSavedQuotes()
            allCaptures = try database.loadAllCaptures()
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

    private func aiContextDescription(attachments: [AIAttachment] = []) -> String {
        let book = selectedBook
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
            let learnings = chapter.learnings.isEmpty ? "" : " Chapter learnings: \(chapter.learnings)"
            return "\(index + 1). \(chapter.title)\(pages): \(chapter.summary)\(learnings)"
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

        let standaloneQuoteMap = savedQuotes.prefix(24).enumerated().map { index, quote in
            let tagList = quote.tags.isEmpty ? "" : " tags: \(quote.tags.joined(separator: ", "))"
            let note = quote.note.isEmpty ? "" : " note: \(quote.note)"
            return "\(index + 1). \(quote.text) — \(quote.attribution)\(tagList)\(note)"
        }.joined(separator: "\n")

        let selectedChapterText = selectedChapter.map { chapter in
            "Current chapter: \(chapter.title)\nSummary: \(chapter.summary)\nChapter learnings: \(chapter.learnings.isEmpty ? "None yet." : chapter.learnings)"
        } ?? "Current chapter: none selected."

        let selectedQuoteText = selectedQuote.map { quote in
            """
            Selected quote:
            \(quote.text)
            Note: \(quote.note.isEmpty ? "None" : quote.note)
            Tags: \(quote.tags.isEmpty ? "None" : quote.tags.joined(separator: ", "))
            """
        } ?? "Selected quote: none selected."

        let attachmentText = attachments.prefix(AIAttachmentPolicy.maxItems).enumerated().map { index, attachment in
            "\(index + 1). \(attachment.promptDescription())"
        }.joined(separator: "\n\n")

        let bookText: String
        if let book {
            bookText = """
            Book:
            Title: \(book.title)
            Display title: \(book.displayTitle)
            Author: \(book.displayAuthor)
            ISBN: \(book.isbn.isEmpty ? "None" : book.isbn)
            Summary: \(book.summary.isEmpty ? "None" : book.summary)
            User book learnings: \(book.learnings.isEmpty ? "None yet." : book.learnings)
            """
        } else {
            bookText = """
            Book:
            No selected book. Use standalone quotes context.
            """
        }

        return """
        \(bookText)

        \(selectedChapterText)

        \(selectedQuoteText)

        Chapter map:
        \(chapterMap.isEmpty ? "No chapters yet." : chapterMap)

        Book quotes:
        \(quoteMap.isEmpty ? "No book quotes yet." : quoteMap)

        Standalone quotes:
        \(standaloneQuoteMap.isEmpty ? "No standalone quotes yet." : standaloneQuoteMap)

        Recent captures:
        \(captureMap.isEmpty ? "No captures yet." : captureMap)

        Active user attachments for this AI turn:
        \(attachmentText.isEmpty ? "None." : attachmentText)
        """
    }

    private func attachmentKind(for type: CaptureType) -> AIAttachmentKind {
        switch type {
        case .pdfPage:
            .pdf
        case .imageFile, .screenshot:
            .image
        case .webURL:
            .web
        case .manualText:
            .text
        }
    }

    private func sourceType(for type: CaptureType) -> SourceType {
        switch type {
        case .pdfPage:
            .pdf
        case .imageFile:
            .image
        case .screenshot:
            .screenshot
        case .webURL:
            .web
        case .manualText:
            .manual
        }
    }

    private func socialShareText(quote: Quote, book: Book) -> String {
        var parts = ["\"\(quote.text)\"", "\(book.displayTitle) - \(book.displayAuthor)"]
        if !quote.pageLocator.isEmpty {
            parts.append(quote.pageLocator)
        }
        parts.append("Saved with NavRead")
        return parts.joined(separator: "\n")
    }

    private func socialShareText(savedQuote: SavedQuote) -> String {
        var parts = ["\"\(savedQuote.text)\""]
        if savedQuote.attribution != "Saved quote" {
            parts.append(savedQuote.attribution)
        }
        if !savedQuote.note.isEmpty {
            parts.append(savedQuote.note)
        }
        parts.append("Saved with NavRead")
        return parts.joined(separator: "\n")
    }

    private func copyQuoteCardToPasteboard(url: URL, quote: Quote, book: Book) {
        NSPasteboard.general.clearContents()
        if let image = NSImage(contentsOf: url) {
            NSPasteboard.general.writeObjects([image, url as NSURL])
        } else {
        NSPasteboard.general.writeObjects([url as NSURL])
        }
        NSPasteboard.general.setString(socialShareText(quote: quote, book: book), forType: .string)
    }

    private func copySavedQuoteCardToPasteboard(url: URL, quote: SavedQuote) {
        NSPasteboard.general.clearContents()
        if let image = NSImage(contentsOf: url) {
            NSPasteboard.general.writeObjects([image, url as NSURL])
        } else {
            NSPasteboard.general.writeObjects([url as NSURL])
        }
        NSPasteboard.general.setString(socialShareText(savedQuote: quote), forType: .string)
    }

    private func openShareURL(_ value: String) {
        guard let url = URL(string: value) else { return }
        NSWorkspace.shared.open(url)
    }

    private func urlEncoded(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
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

    private func deleteQuoteCardAssets(for quoteID: UUID) {
        let prefix = quoteID.uuidString
        guard let files = try? FileManager.default.contentsOfDirectory(at: LibraryPaths.cards, includingPropertiesForKeys: nil) else { return }
        for url in files where url.lastPathComponent.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func deleteSavedQuoteCardAssets(for quoteID: UUID) {
        let prefix = "saved-\(quoteID.uuidString)"
        guard let files = try? FileManager.default.contentsOfDirectory(at: LibraryPaths.cards, includingPropertiesForKeys: nil) else { return }
        for url in files where url.lastPathComponent.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: url)
        }
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

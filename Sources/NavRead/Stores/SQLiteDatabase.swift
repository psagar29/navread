import Foundation
import SQLite3

enum SQLiteError: Error, LocalizedError {
    case open(String)
    case prepare(String)
    case step(String)
    case bind(String)

    var errorDescription: String? {
        switch self {
        case .open(let message), .prepare(let message), .step(let message), .bind(let message):
            message
        }
    }
}

final class SQLiteDatabase {
    private var db: OpaquePointer?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(path: URL) throws {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        if sqlite3_open(path.path, &db) != SQLITE_OK {
            throw SQLiteError.open(lastError)
        }
        try execute("PRAGMA foreign_keys = ON;")
        try migrate()
    }

    deinit {
        sqlite3_close(db)
    }

    func migrate() throws {
        try execute(
            """
            CREATE TABLE IF NOT EXISTS books (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                nickname TEXT NOT NULL DEFAULT '',
                author TEXT NOT NULL,
                isbn TEXT NOT NULL,
                summary TEXT NOT NULL,
                cover_asset_path TEXT,
                dominant_hex TEXT NOT NULL,
                metadata_source TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS chapters (
                id TEXT PRIMARY KEY,
                book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
                title TEXT NOT NULL,
                order_index INTEGER NOT NULL,
                summary TEXT NOT NULL,
                page_start INTEGER,
                page_end INTEGER,
                ai_generated INTEGER NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS captures (
                id TEXT PRIMARY KEY,
                book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
                chapter_id TEXT REFERENCES chapters(id) ON DELETE SET NULL,
                type TEXT NOT NULL,
                raw_text TEXT NOT NULL,
                asset_path TEXT,
                source_url TEXT NOT NULL,
                created_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS quotes (
                id TEXT PRIMARY KEY,
                book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
                chapter_id TEXT REFERENCES chapters(id) ON DELETE SET NULL,
                raw_text TEXT NOT NULL,
                cleaned_text TEXT NOT NULL,
                page_locator TEXT NOT NULL,
                note TEXT NOT NULL,
                tags_json TEXT NOT NULL,
                source_type TEXT NOT NULL,
                source_url TEXT NOT NULL,
                capture_id TEXT REFERENCES captures(id) ON DELETE SET NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS ai_provenance (
                id TEXT PRIMARY KEY,
                model TEXT NOT NULL,
                purpose TEXT NOT NULL,
                input_scope TEXT NOT NULL,
                linked_id TEXT,
                created_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS ai_messages (
                id TEXT PRIMARY KEY,
                scope TEXT NOT NULL,
                linked_id TEXT,
                role TEXT NOT NULL,
                content TEXT NOT NULL,
                created_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS quote_cards (
                id TEXT PRIMARY KEY,
                quote_id TEXT NOT NULL REFERENCES quotes(id) ON DELETE CASCADE,
                theme TEXT NOT NULL,
                format TEXT NOT NULL,
                payload_json TEXT NOT NULL,
                created_at TEXT NOT NULL
            );

            CREATE INDEX IF NOT EXISTS idx_books_updated ON books(updated_at DESC);
            CREATE INDEX IF NOT EXISTS idx_chapters_book ON chapters(book_id, order_index);
            CREATE INDEX IF NOT EXISTS idx_quotes_book ON quotes(book_id, updated_at DESC);
            CREATE INDEX IF NOT EXISTS idx_quotes_chapter ON quotes(chapter_id);
            """
        )
        try addColumnIfNeeded(table: "books", column: "nickname", definition: "TEXT NOT NULL DEFAULT ''")
    }

    func loadBooks() throws -> [Book] {
        try rows(
            """
            SELECT id, title, nickname, author, isbn, summary, cover_asset_path, dominant_hex, metadata_source, created_at, updated_at
            FROM books
            ORDER BY updated_at DESC
            """
        ) { statement in
            Book(
                id: uuid(statement, 0),
                title: text(statement, 1),
                nickname: text(statement, 2),
                author: text(statement, 3),
                isbn: text(statement, 4),
                summary: text(statement, 5),
                coverAssetPath: nullableText(statement, 6),
                dominantHex: text(statement, 7),
                metadataSource: text(statement, 8),
                createdAt: date(statement, 9),
                updatedAt: date(statement, 10)
            )
        }
    }

    func loadChapters(bookID: UUID) throws -> [Chapter] {
        try rows("SELECT * FROM chapters WHERE book_id = ? ORDER BY order_index ASC", [bookID.uuidString]) { statement in
            Chapter(
                id: uuid(statement, 0),
                bookID: uuid(statement, 1),
                title: text(statement, 2),
                orderIndex: Int(sqlite3_column_int(statement, 3)),
                summary: text(statement, 4),
                pageStart: nullableInt(statement, 5),
                pageEnd: nullableInt(statement, 6),
                aiGenerated: sqlite3_column_int(statement, 7) == 1,
                createdAt: date(statement, 8),
                updatedAt: date(statement, 9)
            )
        }
    }

    func loadQuotes(bookID: UUID) throws -> [Quote] {
        try rows("SELECT * FROM quotes WHERE book_id = ? ORDER BY updated_at DESC", [bookID.uuidString]) { statement in
            Self.mapQuote(statement)
        }
    }

    func loadAllQuotes() throws -> [Quote] {
        try rows("SELECT * FROM quotes ORDER BY updated_at DESC") { statement in
            Self.mapQuote(statement)
        }
    }

    func loadCaptures(bookID: UUID) throws -> [Capture] {
        try rows("SELECT * FROM captures WHERE book_id = ? ORDER BY created_at DESC", [bookID.uuidString]) { statement in
            Capture(
                id: uuid(statement, 0),
                bookID: uuid(statement, 1),
                chapterID: nullableUUID(statement, 2),
                type: CaptureType(rawValue: text(statement, 3)) ?? .manualText,
                rawText: text(statement, 4),
                assetPath: nullableText(statement, 5),
                sourceURL: text(statement, 6),
                createdAt: date(statement, 7)
            )
        }
    }

    func insert(book: Book) throws {
        try run(
            """
            INSERT OR REPLACE INTO books
            (id, title, nickname, author, isbn, summary, cover_asset_path, dominant_hex, metadata_source, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                book.id.uuidString, book.title, book.nickname, book.author, book.isbn, book.summary, book.coverAssetPath as Any,
                book.dominantHex, book.metadataSource, iso(book.createdAt), iso(book.updatedAt)
            ]
        )
    }

    func insert(chapter: Chapter) throws {
        try run(
            """
            INSERT OR REPLACE INTO chapters
            (id, book_id, title, order_index, summary, page_start, page_end, ai_generated, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                chapter.id.uuidString, chapter.bookID.uuidString, chapter.title, chapter.orderIndex,
                chapter.summary, chapter.pageStart as Any, chapter.pageEnd as Any, chapter.aiGenerated ? 1 : 0,
                iso(chapter.createdAt), iso(chapter.updatedAt)
            ]
        )
    }

    func insert(quote: Quote) throws {
        let tags = try String(data: encoder.encode(quote.tags), encoding: .utf8) ?? "[]"
        try run(
            """
            INSERT OR REPLACE INTO quotes
            (id, book_id, chapter_id, raw_text, cleaned_text, page_locator, note, tags_json, source_type, source_url, capture_id, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                quote.id.uuidString, quote.bookID.uuidString, quote.chapterID?.uuidString as Any,
                quote.rawText, quote.cleanedText, quote.pageLocator, quote.note, tags, quote.sourceType.rawValue,
                quote.sourceURL, quote.captureID?.uuidString as Any, iso(quote.createdAt), iso(quote.updatedAt)
            ]
        )
    }

    func insert(capture: Capture) throws {
        try run(
            """
            INSERT OR REPLACE INTO captures
            (id, book_id, chapter_id, type, raw_text, asset_path, source_url, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                capture.id.uuidString, capture.bookID.uuidString, capture.chapterID?.uuidString as Any,
                capture.type.rawValue, capture.rawText, capture.assetPath as Any, capture.sourceURL,
                iso(capture.createdAt)
            ]
        )
    }

    func insert(provenance: AIProvenance) throws {
        try run(
            """
            INSERT INTO ai_provenance (id, model, purpose, input_scope, linked_id, created_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            [
                provenance.id.uuidString, provenance.model, provenance.purpose, provenance.inputScope.rawValue,
                provenance.linkedID?.uuidString as Any, iso(provenance.createdAt)
            ]
        )
    }

    func deleteBook(_ id: UUID) throws {
        try run("DELETE FROM ai_provenance WHERE linked_id = ?", [id.uuidString])
        try run("DELETE FROM ai_messages WHERE linked_id = ?", [id.uuidString])
        try run("DELETE FROM books WHERE id = ?", [id.uuidString])
    }

    func deleteAllBooks() throws {
        try run("DELETE FROM books")
    }

    func deleteChapter(_ id: UUID) throws {
        try run("DELETE FROM chapters WHERE id = ?", [id.uuidString])
    }

    func deleteQuote(_ id: UUID) throws {
        try run("DELETE FROM quotes WHERE id = ?", [id.uuidString])
    }

    func run(_ sql: String, _ values: [Any] = []) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteError.prepare(lastError)
        }
        defer { sqlite3_finalize(statement) }
        try bind(values, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteError.step(lastError)
        }
    }

    private func rows<T>(_ sql: String, _ values: [Any] = [], map: (OpaquePointer?) throws -> T) throws -> [T] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteError.prepare(lastError)
        }
        defer { sqlite3_finalize(statement) }
        try bind(values, to: statement)

        var output: [T] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            output.append(try map(statement))
        }
        return output
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw SQLiteError.step(lastError)
        }
    }

    private func addColumnIfNeeded(table: String, column: String, definition: String) throws {
        let columns = try rows("PRAGMA table_info(\(table))") { statement in
            text(statement, 1)
        }
        guard columns.contains(column) == false else { return }
        try execute("ALTER TABLE \(table) ADD COLUMN \(column) \(definition)")
    }

    private static func mapQuote(_ statement: OpaquePointer?) -> Quote {
        Quote(
            id: uuid(statement, 0),
            bookID: uuid(statement, 1),
            chapterID: nullableUUID(statement, 2),
            rawText: text(statement, 3),
            cleanedText: text(statement, 4),
            pageLocator: text(statement, 5),
            note: text(statement, 6),
            tags: decodeStringArray(text(statement, 7)),
            sourceType: SourceType(rawValue: text(statement, 8)) ?? .manual,
            sourceURL: text(statement, 9),
            captureID: nullableUUID(statement, 10),
            createdAt: date(statement, 11),
            updatedAt: date(statement, 12)
        )
    }

    private func bind(_ values: [Any], to statement: OpaquePointer?) throws {
        for (index, value) in values.enumerated() {
            let position = Int32(index + 1)
            switch value {
            case Optional<Any>.none:
                sqlite3_bind_null(statement, position)
            case let value as String:
                sqlite3_bind_text(statement, position, value, -1, SQLITE_TRANSIENT)
            case let value as Int:
                sqlite3_bind_int64(statement, position, sqlite3_int64(value))
            case let value as Int?:
                if let value {
                    sqlite3_bind_int64(statement, position, sqlite3_int64(value))
                } else {
                    sqlite3_bind_null(statement, position)
                }
            case let value as Double:
                sqlite3_bind_double(statement, position, value)
            case let value as Bool:
                sqlite3_bind_int(statement, position, value ? 1 : 0)
            default:
                if value is NSNull {
                    sqlite3_bind_null(statement, position)
                } else {
                    throw SQLiteError.bind("Unsupported SQLite bind value \(value)")
                }
            }
        }
    }

    private var lastError: String {
        String(cString: sqlite3_errmsg(db))
    }

    private func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private func text(_ statement: OpaquePointer?, _ index: Int32) -> String {
    guard let pointer = sqlite3_column_text(statement, index) else { return "" }
    return String(cString: pointer)
}

private func nullableText(_ statement: OpaquePointer?, _ index: Int32) -> String? {
    guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
    return text(statement, index)
}

private func uuid(_ statement: OpaquePointer?, _ index: Int32) -> UUID {
    UUID(uuidString: text(statement, index)) ?? UUID()
}

private func nullableUUID(_ statement: OpaquePointer?, _ index: Int32) -> UUID? {
    guard let raw = nullableText(statement, index) else { return nil }
    return UUID(uuidString: raw)
}

private func nullableInt(_ statement: OpaquePointer?, _ index: Int32) -> Int? {
    guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
    return Int(sqlite3_column_int(statement, index))
}

private func date(_ statement: OpaquePointer?, _ index: Int32) -> Date {
    ISO8601DateFormatter().date(from: text(statement, index)) ?? .now
}

private func decodeStringArray(_ raw: String) -> [String] {
    guard let data = raw.data(using: .utf8),
          let values = try? JSONDecoder().decode([String].self, from: data) else {
        return []
    }
    return values
}

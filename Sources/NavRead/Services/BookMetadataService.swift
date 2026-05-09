import Foundation

actor BookMetadataService {
    func resolve(title: String, author: String, isbn: String) async -> BookMetadata {
        if !isbn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let google = await searchGoogleBooks(query: "isbn:\(isbn)") {
                return google
            }
            if let open = await searchOpenLibrary(title: title, author: author, isbn: isbn) {
                return open
            }
        }

        let titleAuthorQuery = [title, author].filter { !$0.isEmpty }.joined(separator: " ")
        if let google = await searchGoogleBooks(query: titleAuthorQuery) {
            return google
        }
        if let open = await searchOpenLibrary(title: title, author: author, isbn: isbn) {
            return open
        }

        return BookMetadata(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            author: author.trimmingCharacters(in: .whitespacesAndNewlines),
            isbn: isbn.trimmingCharacters(in: .whitespacesAndNewlines),
            summary: "A new reading workspace for quotes, context, and chapter notes.",
            coverURL: nil,
            source: "manual"
        )
    }

    private func searchGoogleBooks(query: String) async -> BookMetadata? {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.googleapis.com/books/v1/volumes?q=\(encoded)&maxResults=5") else {
            return nil
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(GoogleBooksResponse.self, from: data)
            guard let info = response.items?.first?.volumeInfo else { return nil }
            let isbn = info.industryIdentifiers?.first(where: { $0.type.contains("ISBN") })?.identifier ?? ""
            return BookMetadata(
                title: info.title ?? query,
                author: info.authors?.joined(separator: ", ") ?? "",
                isbn: isbn,
                summary: info.description ?? "Imported from Google Books.",
                coverURL: info.imageLinks?.thumbnail.flatMap(URL.init(string:)) ?? info.imageLinks?.smallThumbnail.flatMap(URL.init(string:)),
                source: "google-books"
            )
        } catch {
            return nil
        }
    }

    private func searchOpenLibrary(title: String, author: String, isbn: String) async -> BookMetadata? {
        let query: String
        if !isbn.isEmpty {
            query = "isbn=\(isbn)"
        } else {
            let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? title
            let encodedAuthor = author.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? author
            query = "title=\(encodedTitle)&author=\(encodedAuthor)"
        }
        guard let url = URL(string: "https://openlibrary.org/search.json?\(query)&limit=5") else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(OpenLibraryResponse.self, from: data)
            guard let doc = response.docs.first else { return nil }
            let isbn = doc.isbn?.first ?? isbn
            let coverURL = doc.coverI.flatMap { URL(string: "https://covers.openlibrary.org/b/id/\($0)-L.jpg") }
            return BookMetadata(
                title: doc.title,
                author: doc.authorName?.first ?? author,
                isbn: isbn,
                summary: "Imported from Open Library.",
                coverURL: coverURL,
                source: "open-library"
            )
        } catch {
            return nil
        }
    }
}

private struct GoogleBooksResponse: Decodable {
    var items: [GoogleBookItem]?
}

private struct GoogleBookItem: Decodable {
    var volumeInfo: GoogleVolumeInfo
}

private struct GoogleVolumeInfo: Decodable {
    var title: String?
    var authors: [String]?
    var description: String?
    var imageLinks: GoogleImageLinks?
    var industryIdentifiers: [GoogleIdentifier]?
}

private struct GoogleImageLinks: Decodable {
    var smallThumbnail: String?
    var thumbnail: String?
}

private struct GoogleIdentifier: Decodable {
    var type: String
    var identifier: String
}

private struct OpenLibraryResponse: Decodable {
    var docs: [OpenLibraryDoc]
}

private struct OpenLibraryDoc: Decodable {
    var title: String
    var authorName: [String]?
    var isbn: [String]?
    var coverI: Int?

    enum CodingKeys: String, CodingKey {
        case title
        case authorName = "author_name"
        case isbn
        case coverI = "cover_i"
    }
}

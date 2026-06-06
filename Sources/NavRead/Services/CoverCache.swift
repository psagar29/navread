import AppKit
import Foundation

struct CachedCover {
    var path: String?
    var dominantHex: String
}

actor CoverCache {
    func cacheCover(from url: URL?, title: String, author: String) async -> CachedCover {
        guard let url else {
            return makePlaceholder(title: title, author: author)
        }
        let coverURL = url.normalizedCoverURL

        do {
            let (data, response) = try await URLSession.shared.data(from: coverURL)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let image = NSImage(data: data) else {
                return makePlaceholder(title: title, author: author)
            }

            try LibraryPaths.ensure()
            let destination = LibraryPaths.covers.appendingPathComponent("\(UUID().uuidString).jpg")
            try data.write(to: destination, options: .atomic)
            return CachedCover(path: destination.path, dominantHex: image.averageHex())
        } catch {
            return makePlaceholder(title: title, author: author)
        }
    }

    private func makePlaceholder(title: String, author: String) -> CachedCover {
        let palette = ["#6C7A58", "#405F89", "#8B5D33", "#6E4E7A", "#8E4A43", "#2F5F55"]
        let index = placeholderIndex(title: title, author: author, paletteCount: palette.count)
        return CachedCover(path: nil, dominantHex: palette[index])
    }

    private func placeholderIndex(title: String, author: String, paletteCount: Int) -> Int {
        guard paletteCount > 0 else { return 0 }

        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in "\(title)\u{1F}\(author)".utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return Int(hash % UInt64(paletteCount))
    }
}

private extension URL {
    var normalizedCoverURL: URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false),
              components.scheme == "http" else {
            return self
        }
        components.scheme = "https"
        return components.url ?? self
    }
}

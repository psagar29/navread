import Foundation

enum LibraryPaths {
    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("NavRead", isDirectory: true)
    }

    static var database: URL {
        root.appendingPathComponent("NavRead.sqlite")
    }

    static var assets: URL {
        root.appendingPathComponent("Assets", isDirectory: true)
    }

    static var covers: URL {
        assets.appendingPathComponent("Covers", isDirectory: true)
    }

    static var captures: URL {
        assets.appendingPathComponent("Captures", isDirectory: true)
    }

    static var cards: URL {
        assets.appendingPathComponent("Cards", isDirectory: true)
    }

    static var libraryExistsBeforeSetup: Bool {
        FileManager.default.fileExists(atPath: database.path)
    }

    static func ensure() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: covers, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: captures, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cards, withIntermediateDirectories: true)
    }
}

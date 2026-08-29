import Foundation
import os

/// A JSON array of `Element`, held in one file and decoded once. A class so
/// the decode cache survives the call; deliberately neither `Sendable` nor an
/// actor — every owner is an actor holding it `private let`, so the owner's
/// isolation serialises access. Rewriting the whole file per append is the
/// trade: the file stays kilobytes for years. Revisit when that turns false.
final class JSONFileStore<Element: Codable & Sendable> {
    private let fileURL: URL
    private let logger: Logger

    /// What the file holds, decoded the once. `nil` until the first read and
    /// after a failed write or erasure, all of which send the next `load` back
    /// to disk.
    private var cache: [Element]?

    init(directory: URL, fileName: String, category: String) {
        fileURL = directory.appending(path: fileName)
        logger = Logger(category: category)
    }

    /// Everything on disk, oldest first. An unreadable file reads as empty.
    func load() -> [Element] {
        if let cache {
            return cache
        }

        let loaded = read()
        cache = loaded
        return loaded
    }

    private func read() -> [Element] {
        // No file is the normal state until the first write, so it is checked
        // rather than caught — an expected condition should not spend every
        // launch before the first session logging an error.
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            return []
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([Element].self, from: Data(contentsOf: fileURL))
        } catch {
            // Unreadable history is not worth failing a session over, and it is
            // not worth deleting either: leaving the file alone keeps whatever
            // it holds available to a later version that can read it.
            let name = fileURL.lastPathComponent
            logger
                .error(
                    "failed to read \(name, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            return []
        }
    }

    /// Removes the file, leaving the store as it was before its first write.
    /// Deleted rather than overwritten with an empty array: somebody who asked
    /// to be forgotten should not be left with a file whose modification date
    /// says when they gave up, and `load` reads an absent file as ordinary.
    func erase() {
        cache = nil

        // Checked rather than caught, exactly as `load` does: an erasure of a
        // store nothing was ever written to is the normal case for the bolt
        // scores on a watch, not a failure.
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            return
        }

        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            let name = fileURL.lastPathComponent
            logger
                .error(
                    "failed to erase \(name, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
        }
    }

    /// Writes the whole array. A failed write keeps the file's previous
    /// contents (the write is atomic) and drops the cache, so the next `load`
    /// answers from what the file still holds rather than from an edit that
    /// never landed.
    func save(_ elements: [Element]) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            // Sorted keys but not pretty-printed: the whole file is rewritten
            // after every session, and indentation roughly doubles what is
            // written. Sorting keeps two writes of one history byte-identical.
            encoder.outputFormatting = [.sortedKeys]

            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            // Atomic, so a crash mid-write leaves the previous contents rather
            // than a truncated file that reads back as no history at all.
            try encoder.encode(elements).write(to: fileURL, options: .atomic)
            cache = elements
        } catch {
            cache = nil
            let name = fileURL.lastPathComponent
            logger
                .error(
                    "failed to write \(name, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
        }
    }
}

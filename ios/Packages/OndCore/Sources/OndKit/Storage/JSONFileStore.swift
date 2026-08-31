import Foundation
import os

/// A JSON array of `Element`, held in one file and decoded once. A class so
/// the decode cache survives the call; deliberately neither `Sendable` nor an
/// actor — every owner is an actor holding it `private let`, so the owner's
/// isolation serialises access. Rewriting the whole file per append is the
/// trade: the file stays kilobytes for years. Revisit when that turns false.
final class JSONFileStore<Element: Codable & Sendable> {
    /// What the file holds. A file that stopped decoding is its own case. A
    /// caller that writes back what it read has to tell it apart from an empty
    /// file. Given one value for both, that caller writes over history it
    /// could not read.
    enum Contents {
        case decoded([Element])
        case unreadable
    }

    private let fileURL: URL

    /// Where a file that stopped decoding is copied, so the next save cannot
    /// destroy the only record of what was there.
    private let asideURL: URL

    private let logger: Logger

    /// What the file holds, read the once. `nil` until the first read and
    /// after a failed write or erasure, all of which send the next `load` back
    /// to disk.
    private var cache: Contents?

    init(directory: URL, fileName: String, category: String) {
        fileURL = directory.appending(path: fileName)
        asideURL = directory.appending(path: fileName + ".unreadable")
        logger = Logger(category: category)
    }

    /// Everything on disk, oldest first. A file that stopped decoding reads as
    /// empty; `contents()` is how a caller tells the two apart.
    func load() -> [Element] {
        switch contents() {
        case let .decoded(elements): elements
        case .unreadable: []
        }
    }

    /// What the file holds, with the unreadable case kept whole.
    func contents() -> Contents {
        if let cache {
            return cache
        }

        let onDisk = read()
        cache = onDisk
        return onDisk
    }

    private func read() -> Contents {
        // No file is the normal state until the first write, so it is checked
        // rather than caught — an expected condition should not spend every
        // launch before the first session logging an error.
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            return .decoded([])
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try .decoded(decoder.decode([Element].self, from: Data(contentsOf: fileURL)))
        } catch {
            copyAside(error)
            return .unreadable
        }
    }

    /// Copies a file that stopped decoding, the way `DefaultsJSONStore` copies
    /// a payload that stopped decoding. Copied rather than moved: the file
    /// stays in place, so it comes back by itself on the first launch of a
    /// version that can decode it. The copy survives the next save.
    private func copyAside(_ reason: Error) {
        let name = fileURL.lastPathComponent

        // The first copy wins. A second failure, launches later, is a copy of
        // a file the first save already replaced, and taking its place would
        // destroy the older history this exists to hold.
        guard !FileManager.default.fileExists(atPath: asideURL.path(percentEncoded: false)) else {
            logger.notice("failed to read \(name, privacy: .public), a copy is already kept aside")
            return
        }

        do {
            try Data(contentsOf: fileURL).write(to: asideURL, options: .atomic)
            logger.notice(
                "failed to read \(name, privacy: .public), keeping a copy aside: \(reason.localizedDescription, privacy: .public)"
            )
        } catch {
            logger.error(
                "failed to read \(name, privacy: .public) and failed to keep a copy aside: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// True when the file stopped decoding and no copy of its bytes was kept.
    /// A save then has nothing to fall back on, so it must not go ahead.
    private var holdsUnpreservedBytes: Bool {
        guard case .unreadable = contents() else { return false }

        return !FileManager.default.fileExists(atPath: asideURL.path(percentEncoded: false))
    }

    /// Removes the file and any copy kept aside, leaving the store as it was
    /// before its first write. Deleted rather than overwritten with an empty
    /// array: somebody who asked to be forgotten should not be left with a
    /// file whose modification date says when they gave up, and `load` reads
    /// an absent file as ordinary.
    func erase() {
        cache = nil
        remove(fileURL)
        remove(asideURL)
    }

    private func remove(_ url: URL) {
        // Checked rather than caught, exactly as `load` does: an erasure of a
        // store nothing was ever written to is the normal case for the bolt
        // scores on a watch, not a failure.
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return
        }

        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            let name = url.lastPathComponent
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
        // The write is what turns history nobody can read into history nobody
        // has. `copyAside` has already logged why it kept no copy.
        guard !holdsUnpreservedBytes else { return }

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
            cache = .decoded(elements)
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

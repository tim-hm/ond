import Foundation
import os

/// Serves local reference data immediately and refreshes it from the server.
///
/// Local reads prefer the last complete snapshot the server sent. Before one
/// exists, techniques fall back to the bundled catalogue, routes to `.none`,
/// and foundations have no answer until their first successful download. A
/// refresh runs independently and replaces the complete snapshot when it
/// arrives; reading local data never races or cancels it.
///
/// A server snapshot continues to outrank the bundled catalogue after an app
/// update. The seed is never persisted because doing so would make it
/// indistinguishable from data the server actually supplied.
///
/// A struct, not an actor: each write atomically replaces one complete file.
/// The observable models serialize refreshes per kind, and the file operation
/// itself cannot expose a partially written snapshot.
public struct CachedReferenceRepository: TechniqueReading, FoundationReading, RouteReading {
    private static let logger = Logger(category: "reference-cache")

    private enum Kind: String, Sendable {
        case techniques
        case foundations
        case routes
    }

    private let network: any ReferenceFetching
    private let techniquesURL: URL
    private let foundationsURL: URL
    private let routesURL: URL
    private let seed: [Technique]?

    /// The last decoded snapshot per file, so repeated local reads do not
    /// decode the same complete JSON value. References inside the struct on
    /// purpose: repository copies share the same memory exactly as they share
    /// the files.
    private let decodedTechniques = Snapshot<[Technique]>()
    private let decodedFoundations = Snapshot<[FoundationTopic]>()
    private let decodedRoutes = Snapshot<Routes>()

    /// - Parameters:
    ///   - network: the repository that actually fetches — wrapped, not
    ///     replaced, so this type never learns about the wire format.
    ///   - directory: where the snapshots live. Defaults to Application
    ///     Support — data the system backs up and never purges, unlike Caches,
    ///     which would let the OS delete exactly the copy offline needs.
    ///     Tests pass a temporary directory.
    ///   - seed: the catalogue to fall back to before any fetch has ever
    ///     succeeded. Defaults to the one this build shipped with; a test that
    ///     is about the no-catalogue-at-all path passes `[]`. Empty is stored as
    ///     no seed rather than as an empty catalogue, so a build whose resource
    ///     failed to decode degrades to the behaviour that predates the seed
    ///     instead of insisting there are no techniques.
    public init(
        caching network: any ReferenceFetching,
        directory: URL = .applicationSupportDirectory,
        seed: [Technique] = CatalogueExport.bundled
    ) {
        self.network = network
        techniquesURL = directory.appending(path: "catalogue.json")
        foundationsURL = directory.appending(path: "foundations.json")
        routesURL = directory.appending(path: "routes.json")
        self.seed = seed.isEmpty ? nil : seed
    }

    public func localTechniques() async -> [Technique]? {
        local(
            at: techniquesURL,
            memo: decodedTechniques,
            kind: .techniques,
            seed: seed
        )
    }

    public func refreshTechniques() async throws -> [Technique] {
        try await refresh(
            from: { try await network.listTechniques() },
            storingAt: techniquesURL,
            memo: decodedTechniques,
            kind: .techniques
        )
    }

    public func localFoundations() async -> [FoundationTopic]? {
        local(
            at: foundationsURL,
            memo: decodedFoundations,
            kind: .foundations
        )
    }

    public func refreshFoundations() async throws -> [FoundationTopic] {
        try await refresh(
            from: { try await network.listFoundations() },
            storingAt: foundationsURL,
            memo: decodedFoundations,
            kind: .foundations
        )
    }

    public func localRoutes() async -> Routes? {
        local(
            at: routesURL,
            memo: decodedRoutes,
            kind: .routes,
            seed: .some(.none)
        )
    }

    public func refreshRoutes() async throws -> Routes {
        try await refresh(
            from: { try await network.listRoutes() },
            storingAt: routesURL,
            memo: decodedRoutes,
            kind: .routes
        )
    }

    /// Resolves the best value already on the device without touching the
    /// network. A server snapshot outranks a bundled seed because it is the last
    /// value the authoritative source actually supplied.
    private func local<Value: Codable & Sendable>(
        at url: URL,
        memo: Snapshot<Value>,
        kind: Kind,
        seed: Value? = nil
    ) -> Value? {
        memo.value ?? restored(from: url, into: memo, kind: kind) ?? seed
    }

    /// Fetches and persists a complete reference value. There is deliberately
    /// no deadline here: a local read has already kept the screen moving, so a
    /// slow successful response is still useful and must not be cancelled.
    private func refresh<Value: Codable & Sendable>(
        from network: @escaping @Sendable () async throws -> Value,
        storingAt url: URL,
        memo: Snapshot<Value>,
        kind: Kind
    ) async throws -> Value {
        let fresh = try await network()
        persist(fresh, at: url, memo: memo, kind: kind)
        return fresh
    }

    /// Failure is logged and swallowed: the fresh reference data in hand is
    /// what the caller came for, and an unwritable cache is tomorrow's problem,
    /// not a reason to fail today's fetch.
    private func persist<Value: Codable & Sendable>(
        _ value: Value,
        at url: URL,
        memo: Snapshot<Value>,
        kind: Kind
    ) {
        // Fresh from the server, so it is the memo's next answer whether or
        // not the write below lands.
        memo.value = value
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            // Atomic, so a crash mid-write leaves the previous snapshot rather
            // than a truncated file that reads back as no catalogue at all.
            try JSONEncoder().encode(value).write(to: url, options: .atomic)
        } catch {
            Self.logger
                .notice(
                    "failed to cache \(kind.rawValue, privacy: .public) reference data: \(error.localizedDescription, privacy: .public)"
                )
        }
    }

    /// Restores a snapshot and remembers a successful decode for later reads.
    private func restored<Value: Codable & Sendable>(
        from url: URL,
        into memo: Snapshot<Value>,
        kind: Kind
    ) -> Value? {
        let decoded: Value? = restore(from: url, kind: kind)
        if let decoded {
            memo.value = decoded
        }
        return decoded
    }

    private func restore<Value: Decodable>(from url: URL, kind: Kind) -> Value? {
        // No file is the normal state until the first successful fetch, so it
        // is checked rather than caught — an expected condition should not log
        // as an error.
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return nil
        }

        do {
            return try JSONDecoder().decode(Value.self, from: Data(contentsOf: url))
        } catch {
            Self.logger
                .notice(
                    "failed to read cached \(kind.rawValue, privacy: .public) reference data: \(error.localizedDescription, privacy: .public)"
                )
            return nil
        }
    }
}

/// One decoded snapshot behind a lock.
///
/// `UserDefaults`-style thread safety in miniature, for the same reason
/// `SyncLedger` confines its `@unchecked`: the lock is the whole of the
/// invariant, and keeping it in one ten-line type beats spreading an
/// unexplained exception through the repository.
///
/// Shared with `CachedUserTechniqueRepository`, which memoises its own snapshot
/// on exactly these terms.
final class Snapshot<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value?

    var value: Value? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

import Foundation
import os

/// Serves local reference data immediately and refreshes it from the server.
/// Reads prefer the last complete server snapshot, then the bundled seed —
/// never persisted, or it would look like server data. The occasions file was
/// `routes.json` once; nothing migrates it (önd has no users), but a rename
/// after launch would not be free. A struct: writes atomically replace files.
public struct CachedReferenceRepository: TechniqueReading, FoundationReading, OccasionReading {
    private static let logger = Logger(category: "reference-cache")

    private enum Kind: String, Sendable {
        case techniques
        case foundations
        case occasions
    }

    private let network: any ReferenceFetching
    private let techniquesURL: URL
    private let foundationsURL: URL
    private let occasionsURL: URL
    /// Deferred, and it matters: reading it decodes the whole bundled export.
    /// See the `seed` parameter below.
    private let seed: @Sendable () -> CatalogueExport.Bundled

    /// The last decoded snapshot per file, so repeated local reads do not
    /// decode the same complete JSON value. References inside the struct on
    /// purpose: repository copies share the same memory exactly as they share
    /// the files.
    private let decodedTechniques = Snapshot<[Technique]>()
    private let decodedFoundations = Snapshot<[FoundationTopic]>()
    private let decodedOccasions = Snapshot<OccasionCatalogue>()

    /// `directory` defaults to Application Support — backed up and never
    /// purged, unlike Caches, which the OS could empty of the one copy offline
    /// needs. `seed` is an autoclosure because naming `CatalogueExport.bundled`
    /// decodes the whole export; by value it would run inside both apps'
    /// synchronous `App.init()` on every launch, snapshot on disk or not.
    public init(
        caching network: any ReferenceFetching,
        directory: URL = .applicationSupportDirectory,
        seed: @escaping @Sendable @autoclosure () -> CatalogueExport.Bundled = CatalogueExport
            .bundled
    ) {
        self.network = network
        techniquesURL = directory.appending(path: "catalogue.json")
        foundationsURL = directory.appending(path: "foundations.json")
        occasionsURL = directory.appending(path: "occasions.json")
        self.seed = seed
    }

    public func localTechniques() async -> [Technique]? {
        local(
            at: techniquesURL,
            memo: decodedTechniques,
            kind: .techniques,
            seed: seed().techniques.nilIfEmpty
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
            kind: .foundations,
            seed: seed().foundations.nilIfEmpty
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

    /// Never nil, unlike the two above: an occasion list is a layer *over* the
    /// catalogue, so having none of them is a state every reader already has to
    /// draw rather than a screen with nothing to say. A build whose seed could
    /// not be read answers `.none` and looks exactly like the release that
    /// predates the bundled routing layer.
    public func localOccasions() async -> OccasionCatalogue? {
        local(
            at: occasionsURL,
            memo: decodedOccasions,
            kind: .occasions,
            seed: seed().occasions
        )
    }

    public func refreshOccasions() async throws -> OccasionCatalogue {
        try await refresh(
            from: { try await network.listOccasions() },
            storingAt: occasionsURL,
            memo: decodedOccasions,
            kind: .occasions
        )
    }

    /// Resolves the best value already on the device without touching the
    /// network; a server snapshot outranks a bundled seed. The seed parameter
    /// is an autoclosure so it stays last in fact as well as in the expression
    /// — reading it decodes the whole bundled export. No default, so every
    /// kind having a seed answer is something the signature states.
    private func local<Value: Codable & Sendable>(
        at url: URL,
        memo: Snapshot<Value>,
        kind: Kind,
        seed: @autoclosure () -> Value?
    ) -> Value? {
        memo.value ?? restored(from: url, into: memo, kind: kind) ?? seed()
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

/// One decoded snapshot behind a lock. The lock is the whole of the
/// invariant, so the `@unchecked` is confined to one ten-line type — the same
/// terms as `SyncLedger`. Shared with `CachedUserTechniqueRepository`.
final class Snapshot<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value?

    var value: Value? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

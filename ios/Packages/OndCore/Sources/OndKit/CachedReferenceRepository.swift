import Foundation
import os

/// Serves local reference data immediately and refreshes it from the server.
///
/// The offline-first seam for reference data, in three layers, most authoritative
/// first:
///
/// 1. **The last snapshot the server sent**, available without putting the
///    network in front of a screen. This covers decode failures as well as
///    transport ones: reference data this build once represented stays
///    representable, however far the server has moved on.
/// 2. **A refresh from the server**, which atomically replaces that snapshot
///    whenever it arrives. Reading local data never cancels this request.
/// 3. **The catalogue this build shipped with**, when there is no snapshot at
///    all. A device that has never reached the server still lists every
///    technique, which for a breathing app is the whole promise — the moment
///    somebody most needs it is the moment they have no signal.
///
/// A snapshot outranks the seed even when the app has since been updated with a
/// newer one. The snapshot is the only copy the server has ever vouched for, and
/// preferring it means nobody who has talked to the server is ever moved back
/// onto a build-time guess.
///
/// The seed is never persisted. It is in the bundle already, and writing it to
/// disk would make it indistinguishable from a catalogue the server actually
/// sent — which is the one distinction layer 2 rests on.
///
/// Only foundations have no local answer on a first launch: the export carries
/// techniques alone, so the first successful server response is what creates
/// their offline copy. Routes start at none of themselves because an empty
/// routing layer is valid where an empty breathing catalogue is not.
///
/// A struct, not an actor: each write atomically replaces one complete file.
/// The observable models serialize refreshes per kind, and the file operation
/// itself cannot expose a partially written snapshot.
public struct CachedReferenceRepository: TechniqueReading, FoundationReading, RouteReading {
    private static let logger = Logger(category: "reference-cache")

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
            fallback: techniquesURL,
            memo: decodedTechniques,
            seed: seed
        )
    }

    public func refreshTechniques() async throws -> [Technique] {
        try await refresh(
            from: { try await network.listTechniques() },
            storingAt: techniquesURL,
            memo: decodedTechniques
        )
    }

    public func localFoundations() async -> [FoundationTopic]? {
        local(
            fallback: foundationsURL,
            memo: decodedFoundations
        )
    }

    public func refreshFoundations() async throws -> [FoundationTopic] {
        try await refresh(
            from: { try await network.listFoundations() },
            storingAt: foundationsURL,
            memo: decodedFoundations
        )
    }

    public func localRoutes() async -> Routes? {
        local(
            fallback: routesURL,
            memo: decodedRoutes,
            seed: .some(.none)
        )
    }

    public func refreshRoutes() async throws -> Routes {
        try await refresh(
            from: { try await network.listRoutes() },
            storingAt: routesURL,
            memo: decodedRoutes
        )
    }

    /// Resolves the best value already on the device without touching the
    /// network. A server snapshot outranks a bundled seed because it is the last
    /// value the authoritative source actually supplied.
    private func local<Value: Codable & Sendable>(
        fallback url: URL,
        memo: Snapshot<Value>,
        seed: Value? = nil
    ) -> Value? {
        memo.value ?? restored(from: url, into: memo) ?? seed
    }

    /// Fetches and persists a complete reference value. There is deliberately
    /// no deadline here: a local read has already kept the screen moving, so a
    /// slow successful response is still useful and must not be cancelled.
    private func refresh<Value: Codable & Sendable>(
        from network: @escaping @Sendable () async throws -> Value,
        storingAt url: URL,
        memo: Snapshot<Value>
    ) async throws -> Value {
        let fresh = try await network()
        persist(fresh, at: url, memo: memo)
        return fresh
    }

    /// Failure is logged and swallowed: the fresh reference data in hand is
    /// what the caller came for, and an unwritable cache is tomorrow's problem,
    /// not a reason to fail today's fetch.
    private func persist<Value: Codable & Sendable>(
        _ value: Value,
        at url: URL,
        memo: Snapshot<Value>
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
                .error(
                    "failed to cache reference data: \(error.localizedDescription, privacy: .public)"
                )
        }
    }

    /// [`restore`](CachedReferenceRepository.restore), remembering a
    /// successful decode so the next call reads memory.
    private func restored<Value: Codable & Sendable>(
        from url: URL,
        into memo: Snapshot<Value>
    ) -> Value? {
        let decoded: Value? = restore(from: url)
        if let decoded {
            memo.value = decoded
        }
        return decoded
    }

    private func restore<Value: Decodable>(from url: URL) -> Value? {
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
                .error(
                    "failed to read cached reference data: \(error.localizedDescription, privacy: .public)"
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
private final class Snapshot<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value?

    var value: Value? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

import Foundation
import os

/// Serves a catalogue the server did not send when the current one cannot be
/// fetched, or cannot be fetched quickly.
///
/// The offline-first seam for reference data, in three layers, most authoritative
/// first:
///
/// 1. **The server**, when it answers inside the deadline. Every success is
///    written to disk.
/// 2. **The last snapshot the server sent**, when the fetch fails or misses the
///    deadline — so being unreachable, or unreachably slow, costs at most
///    freshness. This covers decode failures as well as transport ones: a
///    catalogue this build once represented stays representable, however far the
///    server has moved on.
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
/// Only foundations can still fail outright: the export carries techniques
/// alone, so there is nothing to seed them with, and a first-ever launch out of
/// range sees the original error.
///
/// A struct, not an actor: each write atomically replaces a whole file, and
/// concurrent loads can only race to write equivalent snapshots — last one
/// wins, nothing interleaves.
public struct CachedTechniqueRepository: TechniqueReading {
    private static let logger = Logger(category: "catalogue-cache")

    private let network: any TechniqueReading
    private let techniquesURL: URL
    private let foundationsURL: URL
    private let seed: [Technique]?
    private let deadline: Duration

    /// The last decoded snapshot per file, so the offline copy is not read and
    /// fully decoded on every call only to be discarded whenever the network
    /// wins the race — which is the common case. References inside the struct
    /// on purpose: the repository stays the value type its doc argues for,
    /// while the memo is shared across copies exactly as the files are.
    private let decodedTechniques = Snapshot<[Technique]>()
    private let decodedFoundations = Snapshot<[FoundationTopic]>()

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
    ///   - deadline: how long a fetch may hold the caller once there is a
    ///     catalogue to fall back to. Deliberately far shorter than the request
    ///     timeout: a captive portal or a stalled cellular handover keeps a
    ///     socket open for tens of seconds, and the app's first screen is not
    ///     entitled to any of them while a good catalogue sits beside it. Long
    ///     enough that a healthy round trip still wins, so what somebody sees is
    ///     normally today's catalogue rather than yesterday's.
    public init(
        caching network: any TechniqueReading,
        directory: URL = .applicationSupportDirectory,
        seed: [Technique] = CatalogueExport.bundled,
        deadline: Duration = .milliseconds(1500)
    ) {
        self.network = network
        techniquesURL = directory.appending(path: "catalogue.json")
        foundationsURL = directory.appending(path: "foundations.json")
        self.seed = seed.isEmpty ? nil : seed
        self.deadline = deadline
    }

    public func listTechniques() async throws -> [Technique] {
        try await fetch(
            from: { try await network.listTechniques() },
            fallback: techniquesURL,
            memo: decodedTechniques,
            seed: seed
        )
    }

    public func listFoundations() async throws -> [FoundationTopic] {
        try await fetch(
            from: { try await network.listFoundations() },
            fallback: foundationsURL,
            memo: decodedFoundations
        )
    }

    /// The offline copy is resolved before the fetch is awaited, not after it
    /// fails.
    ///
    /// The other way round makes the network a gate in front of it: airplane
    /// mode happens to work because it fails fast, while a captive portal holds
    /// the first screen on a spinner for the whole request timeout with a
    /// perfectly good catalogue already in hand.
    ///
    /// The cost is that a link *consistently* slower than the deadline loses
    /// every race, and its snapshot then never advances — freshness traded for a
    /// first screen, which is the trade this whole type exists to make. Letting
    /// the loser finish and write anyway would need it to outlive the group, and
    /// a group does not return until its children have.
    ///
    /// The seed widens that trade rather than changing it. A first-ever launch
    /// used to have no fallback and so gave the fetch as long as it wanted,
    /// which meant the first snapshot always got written; now such a launch
    /// races like any other, and a device that never once answers inside the
    /// deadline stays on the build's catalogue. That is the right way round —
    /// the seed is the catalogue as of this build, and one launch under the
    /// deadline replaces it, where the alternative was a minute of spinner
    /// before anybody could breathe anything.
    private func fetch<Value: Codable & Sendable>(
        from network: @escaping @Sendable () async throws -> Value,
        fallback url: URL,
        memo: Snapshot<Value>,
        seed: Value? = nil
    ) async throws -> Value {
        guard let offline: Value = memo.value ?? restored(from: url, into: memo) ?? seed else {
            // Nothing on disk and nothing in the bundle, so the fetch gets as
            // long as the request timeout allows and its failure is the
            // caller's.
            let fresh = try await network()
            persist(fresh, at: url, memo: memo)
            return fresh
        }

        return await withTaskGroup(of: Value.self) { group in
            group.addTask {
                // A fetch that fails outright is the offline case, and the
                // offline copy is already the answer — no reason to sit out the
                // rest of the deadline for it.
                do {
                    let fresh = try await network()
                    persist(fresh, at: url, memo: memo)
                    return fresh
                } catch {
                    // The one line that makes offline-first observable. Without
                    // it a device serving a months-old catalogue looks exactly
                    // like one that refreshed a second ago.
                    Self.logger
                        .notice(
                            "serving the offline catalogue: \(error.localizedDescription, privacy: .public)"
                        )
                    return offline
                }
            }
            group.addTask { [deadline] in
                try? await Task.sleep(for: deadline)
                return offline
            }

            // Connect cancels the underlying request rather than merely
            // abandoning it, which is what lets this return at the deadline
            // instead of waiting the loser out. `next()` is non-nil while the
            // group has children; the coalesce is what keeps that a fact the
            // compiler checks rather than a force unwrap.
            let first = await group.next() ?? offline
            group.cancelAll()
            return first
        }
    }

    /// Failure is logged and swallowed: the fresh catalogue in hand is what the
    /// caller came for, and an unwritable cache is tomorrow's problem, not a
    /// reason to fail today's fetch.
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
                    "failed to cache the catalogue: \(error.localizedDescription, privacy: .public)"
                )
        }
    }

    /// [`restore`](CachedTechniqueRepository.restore), remembering a
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
                    "failed to read the cached catalogue: \(error.localizedDescription, privacy: .public)"
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

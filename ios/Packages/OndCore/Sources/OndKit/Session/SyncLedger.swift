import Foundation

/// Which ids the server has confirmed, kept in `UserDefaults`. A wrapper
/// rather than a bare `UserDefaults` on the queue for one reason: it is
/// documented as thread-safe but not annotated `Sendable`, so it cannot cross
/// into an actor without the compiler objecting — confining the `@unchecked`
/// here beats spreading an unexplained exception through the queue.
public struct SyncLedger: @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The acknowledged set, pruned to ids that still exist locally.
    ///
    /// Without the pruning the ledger only ever grows, and somebody who has
    /// breathed daily for three years would carry a thousand dead ids into every
    /// launch.
    func acknowledged(_ key: String, keeping present: [UUID]) -> Set<UUID> {
        let stored = defaults.stringArray(forKey: key) ?? []
        return Set(stored.compactMap(UUID.init(uuidString:))).intersection(present)
    }

    /// Writes only on a genuine change. A sync with nothing outstanding is the
    /// common case — every foreground, every finished session — and it would
    /// otherwise rewrite two identical arrays each time. An absent key reads as
    /// the empty set it is, so the first of those quiet syncs does not mint an
    /// empty array either.
    func store(_ ids: Set<UUID>, at key: String) {
        let encoded = ids.map(\.uuidString).sorted()
        guard defaults.stringArray(forKey: key) ?? [] != encoded else { return }

        defaults.set(encoded, forKey: key)
    }

    /// Drops the whole ledger under `key`, rather than pruning it.
    func forget(_ key: String) {
        defaults.removeObject(forKey: key)
    }

    /// Adds ids without pruning — for sessions that arrived from the server and
    /// are therefore acknowledged the moment they land.
    func acknowledge(_ ids: [UUID], at key: String) {
        let stored = defaults.stringArray(forKey: key) ?? []
        store(Set(stored.compactMap(UUID.init(uuidString:))).union(ids), at: key)
    }
}

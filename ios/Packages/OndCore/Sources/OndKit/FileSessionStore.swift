import Foundation

/// Session history as one JSON file.
///
/// An actor because the write is read-modify-write and a session ending while
/// the sync queue is draining the file must not interleave.
public actor FileSessionStore: SessionRecording, TombstoneStoring, PersonalStore {
    private let file: JSONFileStore<SessionRecord>
    private let tombstones: JSONFileStore<UUID>

    /// - Parameter directory: where `sessions.json` lives. Defaults to
    ///   Application Support — user data the system backs up and never purges,
    ///   unlike Caches. Tests pass a temporary directory.
    public init(directory: URL = .applicationSupportDirectory) {
        file = JSONFileStore(
            directory: directory,
            fileName: "sessions.json",
            category: "session-store"
        )
        tombstones = JSONFileStore(
            directory: directory,
            fileName: "deleted-sessions.json",
            category: "session-store"
        )
    }

    public func record(_ session: SessionRecord) async {
        file.save(file.load() + [session])
    }

    /// Adds sessions the server holds and this device does not, skipping any
    /// already here — and any deleted here. The restore path, and the one
    /// place history flows backwards: the Keychain identity survives a
    /// reinstall, so somebody who comes back has a server full of sessions and
    /// an empty file. Matching on id makes this safe to call after every sync.
    public func merge(_ incoming: [SessionRecord]) async -> Bool {
        let held = file.load()
        var unwanted = Set(held.map(\.id)).union(tombstones.load())
        // `insert` also de-duplicates within `incoming` itself: a restore hands
        // over a whole walk of pages in one call, and a server that repeated an
        // id across pages must not double the session in the file.
        let missing = incoming.filter { unwanted.insert($0.id).inserted }
        guard !missing.isEmpty else { return false }

        file.save((held + missing).sorted { $0.startedAt < $1.startedAt })
        return true
    }

    /// Deletes a session and tombstones its id. The tombstone makes the
    /// deletion hold before the server has heard: `merge` skips a tombstoned
    /// id, so a restore cannot hand the session straight back. The sync queue
    /// drains these through `DeleteSessions` and only then calls
    /// `forgetTombstones` — a list of deletions in flight, not a record.
    public func remove(_ id: SessionRecord.ID) async {
        let held = file.load()
        let remaining = held.filter { $0.id != id }
        guard remaining.count != held.count else { return }

        file.save(remaining)
        tombstones.save(tombstones.load() + [id])
    }

    public func recordedSessions() async -> [SessionRecord] {
        file.load()
    }

    public func tombstonedSessions() async -> [SessionRecord.ID] {
        tombstones.load()
    }

    public func forgetTombstones(_ ids: [SessionRecord.ID]) async {
        let forgotten = Set(ids)
        tombstones.save(tombstones.load().filter { !forgotten.contains($0) })
    }

    /// Both files, because both are about the person. The tombstones go
    /// undrained, and rightly: the server they were addressed to no longer
    /// holds the account, so the account erasure is a superset of every
    /// deletion waiting in them.
    public func erase() async {
        file.erase()
        tombstones.erase()
    }
}

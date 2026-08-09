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
    /// already here — and any deleted here, which the server may still hold.
    ///
    /// The restore path, and the one place history flows backwards: the identity
    /// lives in the Keychain and survives a reinstall, so somebody who deletes
    /// the app and comes back has a server full of sessions and an empty file.
    /// Matching on id is what makes this safe to call after every sync.
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

    /// Deletes a session and tombstones its id.
    ///
    /// The tombstone is what makes the deletion hold before the server has
    /// heard about it: `merge` skips a tombstoned id, so a restore between the
    /// deletion and the next sync cannot hand the session straight back. The
    /// sync queue drains these through `DeleteSessions` and only then calls
    /// `forgetTombstones`, so the file is a list of deletions in flight rather
    /// than a permanent record.
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

    /// Both files, because both are about the person: the sessions they
    /// breathed, and the ids of the ones they deleted.
    ///
    /// The tombstones go undrained, which is the right outcome rather than a
    /// loss. They exist to stop a restore handing a deleted session back, and
    /// the server they were addressed to no longer holds the account they would
    /// have named — the deletion the account erasure performs is a superset of
    /// every deletion waiting in them.
    public func erase() async {
        file.erase()
        tombstones.erase()
    }
}

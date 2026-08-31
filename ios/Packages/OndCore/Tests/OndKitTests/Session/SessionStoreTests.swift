import Foundation
import OndKit
import Testing

@Suite("Keeping finished sessions until there is a server to send them to")
struct SessionStoreTests {
    /// A directory of this suite's own, so a run never reads what a previous one
    /// or the host's real app support directory left behind.
    private func temporaryDirectory() -> URL {
        URL.temporaryDirectory.appending(path: "ond-session-store-\(UUID().uuidString)")
    }

    /// A directory holding one file this version cannot decode — the state a
    /// shape change to `SessionRecord` puts a real install into.
    private func directory(holding contents: Data, named name: String) throws -> URL {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try contents.write(to: directory.appending(path: name))
        return directory
    }

    private func record(
        slug: TechniqueSlug = "box-breathing",
        duration: Duration = .milliseconds(128_000),
        completed: Bool = true
    ) -> SessionRecord {
        SessionRecord(
            techniqueSlug: slug,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            duration: duration,
            cyclesCompleted: 8,
            breathCount: 8,
            completed: completed
        )
    }

    /// The store is the only copy of a session until M5 syncs it, so every field
    /// it is trusted with has to survive the file — a dropped `id` would break
    /// the idempotency the sync retries on, and a dropped `completed` would turn
    /// an abandoned session into a finished one.
    @Test("A session survives the round trip through disk intact")
    func roundTripsASession() async {
        let directory = temporaryDirectory()
        let written = record(completed: false)

        await FileSessionStore(directory: directory).record(written)
        let read = await FileSessionStore(directory: directory).recordedSessions()

        #expect(read == [written])
        #expect(read.first?.duration == .milliseconds(128_000))
    }

    @Test("Sessions accumulate in the order they were finished")
    func appendsRatherThanReplaces() async {
        let store = FileSessionStore(directory: temporaryDirectory())

        await store.record(record(slug: "physiological-sigh"))
        await store.record(record(slug: "box-breathing"))
        await store.record(record(slug: "bellows-breath"))

        let slugs = await store.recordedSessions().map(\.techniqueSlug)
        #expect(slugs == ["physiological-sigh", "box-breathing", "bellows-breath"])
    }

    /// The first launch, and every launch until the first session ends.
    @Test("No history yet reads as no sessions, not as a failure")
    func startsEmpty() async {
        let sessions = await FileSessionStore(directory: temporaryDirectory()).recordedSessions()

        #expect(sessions.isEmpty)
    }

    /// Deletion has to hold against the sync: `merge` runs on every restore,
    /// and without the tombstone it would hand a deleted-but-synced session
    /// straight back on the next foreground.
    @Test("A deleted session stays deleted through a merge")
    func deletionSurvivesMerge() async {
        let store = FileSessionStore(directory: temporaryDirectory())
        let kept = record(slug: "box-breathing")
        let deleted = record(slug: "bellows-breath")

        await store.record(kept)
        await store.record(deleted)
        await store.remove(deleted.id)

        #expect(await store.recordedSessions() == [kept])

        // The server still holds both; only the one never deleted may return.
        let changed = await store.merge([kept, deleted])
        #expect(!changed)
        #expect(await store.recordedSessions() == [kept])
    }

    /// Removing an id the store never held must not tombstone it — the same id
    /// arriving later from the server is a session this device simply hadn't
    /// seen yet, not one the person got rid of.
    @Test("Removing an unknown id does not block it from a later merge")
    func unknownRemovalLeavesNoTombstone() async {
        let store = FileSessionStore(directory: temporaryDirectory())
        let incoming = record()

        await store.remove(incoming.id)
        let changed = await store.merge([incoming])

        #expect(changed)
        #expect(await store.recordedSessions() == [incoming])
    }

    /// A tombstone's whole life. It holds the deletion until `DeleteSessions`
    /// has landed and goes the moment it has — kept forever, the file would
    /// grow for the life of the install and filter against ids the server no
    /// longer holds.
    @Test("A tombstone is dropped once the server has forgotten the session")
    func tombstonesAreDrainedRatherThanHoarded() async {
        let store = FileSessionStore(directory: temporaryDirectory())
        let deleted = record()

        await store.record(deleted)
        await store.remove(deleted.id)
        #expect(await store.tombstonedSessions() == [deleted.id])

        await store.forgetTombstones([deleted.id])
        #expect(await store.tombstonedSessions().isEmpty)
    }

    /// The store answers from memory after the first read, so a write the file
    /// refused must not survive in it: a session counted in the totals all day
    /// and gone at the next launch is worse than one that never landed.
    @Test("A refused write leaves the store reporting what the file holds")
    func aRefusedWriteDoesNotLingerInMemory() async throws {
        let directory = temporaryDirectory()
        // A directory where the file belongs, so neither the write nor the
        // re-read can land — as close to a full disk as a test gets.
        try FileManager.default.createDirectory(
            at: directory.appending(path: "sessions.json"),
            withIntermediateDirectories: true
        )
        let store = FileSessionStore(directory: directory)

        await store.record(record())

        #expect(await store.recordedSessions().isEmpty)
    }

    /// Unreadable history must not take a session down with it: the person is
    /// mid-breath and there is nothing they could do about it.
    @Test("Corrupt history reads as empty rather than throwing")
    func survivesCorruptHistory() async throws {
        let directory = try directory(holding: Data("not json".utf8), named: "sessions.json")

        let store = FileSessionStore(directory: directory)
        #expect(await store.recordedSessions().isEmpty)

        await store.record(record())
        #expect(await store.recordedSessions().count == 1)
    }

    /// The next session rewrites the whole file. Unless the bytes it cannot
    /// decode are copied aside first, that write is what turns history nobody
    /// could read into history nobody has.
    @Test("A session recorded over unreadable history keeps the unreadable bytes")
    func recordingKeepsUnreadableHistory() async throws {
        let unreadable = Data(#"[{"techniqueSlug":"box-breathing""#.utf8)
        let directory = try directory(holding: unreadable, named: "sessions.json")
        let store = FileSessionStore(directory: directory)
        let written = record()

        await store.record(written)

        #expect(await store.recordedSessions() == [written])
        let kept = try Data(contentsOf: directory.appending(path: "sessions.json.unreadable"))
        #expect(kept == unreadable)
    }

    /// A deletion list that will not decode names no deletions, and a merge
    /// that believes it hands the person back every session they got rid of.
    @Test("An unreadable deletion list stops a merge rather than resurrecting a session")
    func mergeStopsWithoutADeletionList() async throws {
        let directory = try directory(
            holding: Data("not json".utf8),
            named: "deleted-sessions.json"
        )
        let store = FileSessionStore(directory: directory)

        let changed = await store.merge([record()])

        #expect(!changed)
        #expect(await store.recordedSessions().isEmpty)
    }

    /// The tombstone is what holds the deletion against the next restore. A
    /// history file that will not decode cannot say the session is in it, so
    /// the deletion has to be written down anyway.
    @Test("A deletion is tombstoned even when the history file will not decode")
    func deletionHoldsAgainstUnreadableHistory() async throws {
        let directory = try directory(holding: Data("not json".utf8), named: "sessions.json")
        let store = FileSessionStore(directory: directory)
        let deleted = record()

        await store.remove(deleted.id)

        #expect(await store.tombstonedSessions() == [deleted.id])
        #expect(await store.merge([deleted]) == false)
        #expect(await store.recordedSessions().isEmpty)
    }

    /// An erasure that left the copy behind would not be one: the copy is the
    /// same person's sessions in an encoding this version cannot read.
    @Test("Erasing takes the copy of the unreadable file with it")
    func erasingTakesTheUnreadableCopy() async throws {
        let directory = try directory(holding: Data("not json".utf8), named: "sessions.json")
        let store = FileSessionStore(directory: directory)
        _ = await store.recordedSessions()
        let aside = directory.appending(path: "sessions.json.unreadable")
        #expect(FileManager.default.fileExists(atPath: aside.path(percentEncoded: false)))

        await store.erase()

        #expect(!FileManager.default.fileExists(atPath: aside.path(percentEncoded: false)))
    }

    /// Writing one tombstone over a list that will not decode would make the
    /// list decode again, holding only the newest deletion — and the merge it
    /// unblocks would hand back every deletion the list still owed.
    @Test("A later deletion does not unblock a merge the unreadable list is stopping")
    func aDeletionDoesNotRewriteAnUnreadableDeletionList() async throws {
        let directory = try directory(
            holding: Data("not json".utf8),
            named: "deleted-sessions.json"
        )
        let store = FileSessionStore(directory: directory)
        let breathed = record(slug: "box-breathing")
        await store.record(breathed)

        await store.remove(breathed.id)

        // A session the unreadable list already owed a deletion for.
        #expect(await store.merge([record(slug: "bellows-breath")]) == false)
        #expect(await store.recordedSessions().isEmpty)
    }

    /// The copy aside is what makes the overwrite safe. Where no copy could be
    /// made, the write is refused instead: the person loses the one session
    /// they just finished rather than every session they ever did.
    @Test("A history file no copy could be made of is not written over")
    func anUncopyableHistoryFileIsNotWrittenOver() async throws {
        let held = Data("not json".utf8)
        let directory = try directory(holding: held, named: "sessions.json")
        let history = directory.appending(path: "sessions.json")
        let path = history.path(percentEncoded: false)
        // Write-only, so the bytes can be neither decoded nor copied, while an
        // atomic write over them would still land.
        try FileManager.default.setAttributes([.posixPermissions: 0o222], ofItemAtPath: path)

        await FileSessionStore(directory: directory).record(record())

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path)
        #expect(try Data(contentsOf: history) == held)
    }
}

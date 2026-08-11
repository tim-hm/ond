import Foundation
@testable import OndKit
import Testing

/// The bookkeeping that decides what crosses the network.
///
/// Worth testing because both ways of getting it wrong are invisible: a ledger
/// that forgets sends a person's whole history on every launch, and one that
/// remembers too eagerly loses the sessions a failed request never delivered.
@Suite("Session sync queue")
struct SessionSyncQueueTests {
    @Test("Acknowledged sessions are never sent twice")
    func acknowledgedSessionsAreNotResent() async {
        let sessions = SessionSpy([syncSession(-1), syncSession(-2)])
        let server = ServerSpy()
        let queue = syncQueue(
            sessions: sessions,
            scores: ScoreSpy(),
            journeys: server,
            ledger: SyncLedger(defaults: syncDefaults())
        )

        await queue.sync()
        #expect(await server.received.count == 2)

        await queue.sync()
        #expect(await server.received.count == 2, "a second run has nothing to say")

        await sessions.record(syncSession(0))
        await queue.sync()
        #expect(await server.received.count == 3, "and picks up what arrived since")
    }

    /// The failure that matters: a request that never landed must leave the
    /// ledger alone, or the session it carried is lost to the server forever.
    @Test("A failed send is retried on the next run")
    func aFailedSendIsRetried() async {
        let server = ServerSpy(isReachable: false)
        let queue = syncQueue(
            sessions: SessionSpy([syncSession(-1)]),
            scores: ScoreSpy([BoltScore(seconds: 22)]),
            journeys: server,
            ledger: SyncLedger(defaults: syncDefaults())
        )

        await queue.sync()
        #expect(await server.received.isEmpty)
        #expect(await server.receivedScores.isEmpty)

        await server.comeBackOnline()
        await queue.sync()
        #expect(await server.received.count == 1)
        #expect(await server.receivedScores.count == 1)
    }

    /// The reinstall path. The Keychain identity outlives the sessions file, so
    /// the server can hold history this device has lost — and what comes back
    /// must not be counted as something to send.
    @Test("Restored sessions land locally and are not echoed back")
    func restoredSessionsAreNotEchoedBack() async {
        let theirs = syncSession(-48)
        let sessions = SessionSpy()
        let server = ServerSpy(held: [theirs])
        let queue = syncQueue(
            sessions: sessions,
            scores: ScoreSpy(),
            journeys: server,
            ledger: SyncLedger(defaults: syncDefaults())
        )

        // The return value is "did local state change": true exactly once, on
        // the run that brought the history back — a caller re-reads on it, and
        // the server holding what it already sent us must not trigger that
        // re-read on every sync for the rest of the install.
        #expect(await queue.sync())
        #expect(await sessions.stored.map(\.id) == [theirs.id])
        #expect(await server.received.isEmpty, "it came from there")

        #expect(await !queue.sync())
        #expect(await sessions.stored.count == 1, "and is not duplicated on the way in")
        #expect(await server.received.isEmpty)
    }

    /// The restore is the only thing standing between a reinstall and a lost
    /// journal, and the server bounds what one call returns — so a queue that
    /// took the first page as the whole history would silently drop everything
    /// behind it, while the totals arriving alongside kept saying it was there.
    @Test("A restore keeps paging until the server runs out of history")
    func aRestorePagesUntilTheHistoryIsExhausted() async {
        let held = (1 ... 57).map { syncSession(-$0) }
        let sessions = SessionSpy()
        let server = ServerSpy(held: held, pageSize: 20)
        let queue = syncQueue(
            sessions: sessions,
            scores: ScoreSpy(),
            journeys: server,
            ledger: SyncLedger(defaults: syncDefaults())
        )

        #expect(await queue.sync())
        #expect(
            await Set(sessions.stored.map(\.id)) == Set(held.map(\.id)),
            "every page landed, not only the first"
        )
        #expect(await server.received.isEmpty, "and none of it was echoed back")

        #expect(await !queue.sync(), "and a second run brings nothing new back")
        #expect(await sessions.stored.count == held.count)
    }

    /// The deletion round trip, and the reason it is a round trip at all: the
    /// server holds a copy the local delete cannot reach, so a reinstall would
    /// restore a session the person got rid of. The tombstone is the client's
    /// half of that promise and only leaves once the server has answered.
    @Test("A deleted session is deleted on the server, and only then forgotten")
    func deletionsReachTheServerBeforeTheTombstoneGoes() async {
        let deleted = syncSession(-1)
        let sessions = SessionSpy([deleted, syncSession(-2)])
        let server = ServerSpy(held: [deleted])
        let queue = syncQueue(
            sessions: sessions,
            scores: ScoreSpy(),
            journeys: server,
            tombstones: sessions,
            ledger: SyncLedger(defaults: syncDefaults())
        )

        await queue.sync()
        await sessions.remove(deleted.id)
        #expect(await sessions.tombstoned == [deleted.id])

        await queue.sync()
        #expect(await server.deleted == [deleted.id])
        #expect(await sessions.tombstoned.isEmpty, "the server has forgotten it")
        #expect(
            await sessions.stored.count == 1,
            "and the restore in the same run cannot hand it back"
        )
    }

    /// The mirror of the failed send, and the more dangerous half: a tombstone
    /// dropped on a request that never landed leaves the server holding a
    /// session the person deleted, and the next restore returns it.
    @Test("A failed deletion keeps its tombstone")
    func aFailedDeletionIsRetried() async {
        let deleted = syncSession(-1)
        let sessions = SessionSpy([deleted])
        let server = ServerSpy(isReachable: false, held: [deleted])
        let queue = syncQueue(
            sessions: sessions,
            scores: ScoreSpy(),
            journeys: server,
            tombstones: sessions,
            ledger: SyncLedger(defaults: syncDefaults())
        )

        await sessions.remove(deleted.id)
        await queue.sync()
        #expect(await server.deleted.isEmpty)
        #expect(await sessions.tombstoned == [deleted.id])

        await server.comeBackOnline()
        await queue.sync()
        #expect(await server.deleted == [deleted.id])
        #expect(await sessions.tombstoned.isEmpty)
    }

    /// The deletion invariant under the one interleaving that can break it: an
    /// account erasure while the restore walk is suspended at a page fetch.
    /// Actor reentrancy lets the erasure run mid-walk; a queue without its
    /// identity epoch resumed the walk, merged the erased identity's history
    /// into the freshly emptied store, and re-acknowledged its ids into the
    /// ledger the erasure had just forgotten.
    @Test("An erasure during a suspended restore resurrects nothing")
    func anEraseDuringARestoreResurrectsNothing() async {
        let store = syncDefaults()
        let sessions = SessionSpy()
        let server = ServerSpy(held: [syncSession(-48), syncSession(-24)])
        let queue = syncQueue(
            sessions: sessions,
            scores: ScoreSpy(),
            journeys: server,
            ledger: SyncLedger(defaults: store)
        )

        await server.holdNextRestore()
        let sync = Task { await queue.sync() }
        // Bounded, so a regressed gate fails the test rather than hanging the
        // suite — `settle`'s philosophy, repolled here because the condition
        // lives on an actor.
        for _ in 0 ..< 400 {
            if await server.restoreCalls > 0 {
                break
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
        #expect(await server.restoreCalls == 1, "the walk reached the held page")

        // The composition roots erase the queue before its stores — the order
        // the epoch mechanism documents as load-bearing.
        await queue.erase()
        await sessions.erase()
        await server.releaseRestore()
        _ = await sync.value

        #expect(await sessions.stored.isEmpty, "the erased history stays erased")
        #expect(
            store.stringArray(forKey: "journey.acknowledgedSessions") == nil,
            "the forgotten ledger stays forgotten"
        )

        // The erasure reopened the restore, so the next sync walks again — and
        // this time the history it brings back is whatever the server holds
        // for the identity that now exists.
        await server.hold([])
        #expect(await !queue.sync())
        #expect(await server.restoreCalls > 1)
    }

    /// A sync with nothing outstanding is the common case — every foreground,
    /// every tap on the journey tab — and it must leave the ledger exactly as
    /// it found it: not even an empty array where no key had been.
    @Test("A sync with nothing to say writes nothing to the ledger")
    func aQuietSyncLeavesTheLedgerUntouched() async {
        let store = syncDefaults()
        let queue = syncQueue(
            sessions: SessionSpy(),
            scores: ScoreSpy(),
            journeys: ServerSpy(),
            ledger: SyncLedger(defaults: store)
        )

        await queue.sync()

        #expect(store.stringArray(forKey: "journey.acknowledgedSessions") == nil)
        #expect(store.stringArray(forKey: "journey.acknowledgedBoltScores") == nil)
    }

    /// The ledger is pruned to what still exists, so it cannot grow without
    /// bound over years of daily practice.
    @Test("The ledger does not outlive the sessions it names")
    func theLedgerIsPruned() async {
        let store = syncDefaults()
        let sessions = SessionSpy([syncSession(-1)])
        let queue = syncQueue(
            sessions: sessions,
            scores: ScoreSpy(),
            journeys: ServerSpy(),
            ledger: SyncLedger(defaults: store)
        )

        await queue.sync()
        #expect(store.stringArray(forKey: "journey.acknowledgedSessions")?.count == 1)

        let emptied = syncQueue(
            sessions: SessionSpy(),
            scores: ScoreSpy(),
            journeys: ServerSpy(),
            ledger: SyncLedger(defaults: store)
        )
        await emptied.sync()
        #expect(store.stringArray(forKey: "journey.acknowledgedSessions")?.isEmpty == true)
    }
}

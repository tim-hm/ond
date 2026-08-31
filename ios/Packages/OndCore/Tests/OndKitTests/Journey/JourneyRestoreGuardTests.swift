import Foundation
@testable import OndKit
import Testing

/// When the queue asks the server for history it may not have, and when it
/// stops asking. The guard has grown three exceptions — signing in, the wrist
/// finishing a session the phone ordered, a walk that never finished. All
/// three are invisible when wrong: the journey simply shows less practice.
/// The fourth case, with no exception, is a round trip on every tab tap.
@Suite("Journey restore guard")
struct JourneyRestoreGuardTests {
    /// The journey tab is a `.task`, so it re-runs on every switch back to it.
    /// Restore is the one step that reaches the server with nothing outstanding
    /// — left unguarded it turned every tap on the tab into a round trip, and a
    /// paging one on any install with real history.
    @Test("A restore that has already run does not question the server again")
    func aCompletedRestoreIsNotRepeated() async {
        let server = ServerSpy(held: [syncSession(-48)])
        let queue = syncQueue(
            sessions: SessionSpy(),
            scores: ScoreSpy(),
            journeys: server,
            ledger: SyncLedger(defaults: syncDefaults())
        )

        await queue.sync()
        let afterFirst = await server.restoreCalls
        #expect(afterFirst > 0, "the first run has to ask, or a reinstall stays empty")

        await queue.sync()
        await queue.sync()
        #expect(
            await server.restoreCalls == afterFirst,
            "two further appearances cost nothing on the wire"
        )
    }

    /// The exception that guard has to make. Signing in hands this install the
    /// identity whose history it came for, and the queue is built once at
    /// launch — so a restore already answered under the old id is exactly the
    /// answer that is now stale. Without this, a person restoring their journey
    /// on a second device sees nothing until they next relaunch the app.
    @Test("Adopting an identity restores again, whatever this queue already asked")
    func anAdoptedIdentityRestoresAgain() async {
        let theirs = syncSession(-48)
        let sessions = SessionSpy()
        let server = ServerSpy()
        let queue = syncQueue(
            sessions: sessions,
            scores: ScoreSpy(),
            journeys: server,
            ledger: SyncLedger(defaults: syncDefaults())
        )

        await queue.sync()
        #expect(await sessions.stored.isEmpty, "this device has no history of its own")

        await server.hold([theirs])
        #expect(await queue.sync() == false, "and would never ask a second time")
        #expect(await queue.syncAdoptedIdentity(), "signing in is what asks again")
        #expect(await sessions.stored.map(\.id) == [theirs.id])
    }

    /// The wrist's completion notice, from the queue's side: the same identity
    /// has new server history, because another device just recorded some. One
    /// page answers that, and the answered walk is left exactly as it was.
    @Test("The wrist's notice fetches the newest page whatever the walk already did")
    func theWristsNoticeFetchesTheNewestPage() async {
        let theirs = syncSession(-1)
        let sessions = SessionSpy()
        let server = ServerSpy()
        let queue = syncQueue(
            sessions: sessions,
            scores: ScoreSpy(),
            journeys: server,
            ledger: SyncLedger(defaults: syncDefaults())
        )

        await queue.sync()
        await server.hold([theirs])
        #expect(await queue.sync() == false, "an answered restore does not ask twice")

        #expect(await queue.restoreNewestSessions(), "the wrist's notice is what asks again")
        #expect(await sessions.stored.map(\.id) == [theirs.id])
    }

    /// The reason the notice must not run the walk: the wrist sends it the
    /// moment a session ends, which can be before its own upload has landed.
    /// A reopened walk would find nothing, mark the launch's restore answered,
    /// and hide the session it came for until the app was relaunched.
    @Test("A notice that arrives too early leaves the launch's restore open")
    func anEarlyNoticeDoesNotSpendTheRestore() async {
        let theirs = syncSession(-1)
        let sessions = SessionSpy()
        let server = ServerSpy()
        let queue = syncQueue(
            sessions: sessions,
            scores: ScoreSpy(),
            journeys: server,
            ledger: SyncLedger(defaults: syncDefaults())
        )

        // The notice lands first, on a server that has nothing yet.
        #expect(await queue.restoreNewestSessions() == false)

        await server.hold([theirs])
        #expect(
            await queue.sync(),
            "the launch's own restore is still owed, and still finds the session"
        )
        #expect(await sessions.stored.map(\.id) == [theirs.id])
    }

    /// The other half of that guard: "already run" has to mean the walk
    /// finished, not that it was attempted. A device launched in a tunnel would
    /// otherwise never restore, and a reinstall on it would stay empty for the
    /// life of the install.
    @Test("A restore that failed is asked again on the next run")
    func aFailedRestoreIsRetried() async {
        let theirs = syncSession(-48)
        let sessions = SessionSpy()
        let server = ServerSpy(isReachable: false, held: [theirs])
        let queue = syncQueue(
            sessions: sessions,
            scores: ScoreSpy(),
            journeys: server,
            ledger: SyncLedger(defaults: syncDefaults())
        )

        await queue.sync()
        #expect(await sessions.stored.isEmpty)

        await server.comeBackOnline()
        #expect(await queue.sync(), "the retry is what brings the history back")
        #expect(await sessions.stored.map(\.id) == [theirs.id])
    }
}

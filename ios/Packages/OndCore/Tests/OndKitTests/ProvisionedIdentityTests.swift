import Foundation
@testable import OndKit
import os
import Testing

/// One identity a test needs and does not otherwise care about. Here rather
/// than in a feature's doubles because a dozen suites across the account, the
/// hand-over and the cache all ask for one.
func anIdentity() -> UserId {
    UserId(rawValue: UUID())
}

/// The watch's half of the identity seam, through a fake store — on the host
/// the real Keychain means an unsigned process writing to a developer's login
/// keychain. A watch that minted its own id would split a person's journey in
/// two, silently. "Never mints" is a claim about writes, the caching about
/// reads. File scope because `WatchHandoffInboxTests` provisions through this.
final class FakeStorage: IdentityStorage {
    private struct State {
        var id: UserId?
        var reads = 0
        var writes = 0
        var inserts = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    init(holding id: UserId? = nil) {
        state.withLock { $0.id = id }
    }

    var reads: Int {
        state.withLock { $0.reads }
    }

    var writes: Int {
        state.withLock { $0.writes }
    }

    /// Counted apart from `writes`, because minting and replacing are the two
    /// things a test about identity most needs to tell apart: one invents a
    /// person and the other follows one.
    var inserts: Int {
        state.withLock { $0.inserts }
    }

    func read() -> UserId? {
        state.withLock {
            $0.reads += 1
            return $0.id
        }
    }

    func insert(_ id: UserId) -> UserId? {
        state.withLock {
            $0.inserts += 1
            $0.id = $0.id ?? id
            return $0.id
        }
    }

    func replace(with id: UserId) -> Bool {
        state.withLock {
            $0.id = id
            $0.writes += 1
        }
        return true
    }
}

/// The credential half of a fake Keychain, beside `FakeStorage` and
/// shared the same way. Counts nothing, unlike its neighbour: what the
/// credential cache does with storage is read once and remember, and the
/// tests that care read the answer back through the store rather than
/// through the double.
final class FakeCredentialStorage: CredentialStorage {
    private let stored = OSAllocatedUnfairLock<String?>(initialState: nil)

    func read() -> String? {
        stored.withLock { $0 }
    }

    func replace(with value: String) -> Bool {
        stored.withLock { $0 = value }
        return true
    }

    @discardableResult
    func remove() -> Bool {
        stored.withLock { $0 = nil }
        return true
    }
}

/// The two stores over a fake Keychain whose credential item nothing in the
/// calling test asks about. Most of what these suites pin is about the id alone,
/// and a second argument repeating "and no credential either" on twenty lines
/// would bury the one thing each of them is actually saying. The tests that *are*
/// about the credential name their own storage.
extension KeychainUserIdentityStore {
    convenience init(storage: any IdentityStorage) {
        self.init(storage: storage, credentials: FakeCredentialStorage())
    }
}

extension ProvisionedUserIdentityStore {
    convenience init(storage: any IdentityStorage) {
        self.init(storage: storage, credentials: FakeCredentialStorage())
    }
}

@Suite("Provisioned identity")
struct ProvisionedIdentityTests {
    @Test("An unprovisioned watch is anonymous and stays that way")
    func neverMintsAnIdentity() {
        let storage = FakeStorage()
        let store = ProvisionedUserIdentityStore(storage: storage)

        #expect(store.userId() == nil)
        #expect(store.userId() == nil, "a second read must not mint one either")
        #expect(storage.writes == 0)
    }

    /// A confirmed absence is cached like an id is. Every outbound RPC asks for
    /// the identity, so a watch that has never met its phone would otherwise pay
    /// a Keychain round-trip on each one, forever, to be told nothing again.
    @Test("An absent identity is looked up once, not on every request")
    func cachesTheConfirmedAbsence() {
        let storage = FakeStorage()
        let store = ProvisionedUserIdentityStore(storage: storage)

        _ = store.userId()
        _ = store.userId()

        #expect(storage.reads == 1)
    }

    @Test("The handed-over id is stored and answered from then on")
    func adoptsTheHandedOverId() {
        let store = ProvisionedUserIdentityStore(storage: FakeStorage())
        let id = anIdentity()

        #expect(store.adopt(userId: id))
        #expect(store.userId() == id)
    }

    /// The phone re-sends its context on every launch, and a watch that treated
    /// each one as news would kick a sync it has nothing to say in.
    @Test("Re-sending the same id changes nothing")
    func ignoresARepeatedHandover() {
        let id = anIdentity()
        let storage = FakeStorage(holding: id)
        let store = ProvisionedUserIdentityStore(storage: storage)

        #expect(store.adopt(userId: id) == false)
        #expect(storage.writes == 0)
    }

    /// Somebody who reinstalled the phone app arrives with a new id. The phone
    /// is the authority, so the watch follows rather than keeping an identity
    /// nothing else writes to.
    @Test("A different id replaces the stored one")
    func followsThePhoneToANewId() {
        let storage = FakeStorage(holding: anIdentity())
        let store = ProvisionedUserIdentityStore(storage: storage)
        let replacement = anIdentity()

        #expect(store.adopt(userId: replacement))
        #expect(store.userId() == replacement)
        #expect(storage.read() == replacement)
    }
}

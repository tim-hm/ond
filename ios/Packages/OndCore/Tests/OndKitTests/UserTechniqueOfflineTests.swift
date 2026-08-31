import Foundation
@testable import OndKit
import Testing

/// One identity, and a second one to swap to. Distinct is the whole
/// requirement; which two they are never matters.
private let someone = anIdentity()
private let somebodyElse = anIdentity()

/// The half of the boundary that talks to the server, scripted.
private actor ScriptedServer: UserTechniqueStoring {
    private var list: UserTechniqueList
    private var failing: Bool
    private(set) var lists = 0

    init(_ list: UserTechniqueList, failing: Bool = false) {
        self.list = list
        self.failing = failing
    }

    func startFailing() {
        failing = true
    }

    func listUserTechniques() async throws -> UserTechniqueList {
        lists += 1
        if failing {
            throw UserTechniqueRepositoryError.transport(.stub())
        }
        return list
    }

    func createUserTechnique(_ draft: TechniqueDraft) async throws -> Technique {
        if failing {
            throw UserTechniqueRepositoryError.transport(.stub())
        }
        return stored(draft, id: "created")
    }

    func updateUserTechnique(id: TechniqueId, to _: TechniqueDraft) async throws -> Technique {
        if failing {
            throw UserTechniqueRepositoryError.transport(.stub())
        }
        return stored(draft(name: "updated"), id: id.rawValue)
    }

    func deleteUserTechnique(id _: TechniqueId) async throws {
        if failing {
            throw UserTechniqueRepositoryError.transport(.stub())
        }
    }
}

private func list(_ ids: [String]) -> UserTechniqueList {
    UserTechniqueList(
        techniques: ids.map { stored(draft(name: $0), id: $0) },
        limits: limits
    )
}

/// What the "Yours" section does when the server is not there.
///
/// The regression behind every test here: the section had no local copy at all,
/// so a refresh that could not reach the server replaced a drawn list with an
/// error — beside a catalogue that kept rendering, from its own cache.
@Suite("Somebody's own exercises, offline")
struct UserTechniqueOfflineTests {
    /// A fresh directory per test, so one test's snapshot is never another's
    /// starting state.
    private func directory() -> URL {
        let url = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("A fetch is served back without the server, once it has succeeded once")
    func aSuccessfulFetchIsReadableOffline() async throws {
        let directory = directory()
        let identity = mintingStore(holding: someone)
        let server = ScriptedServer(list(["a", "b"]))
        let cache = CachedUserTechniqueRepository(
            caching: server,
            identity: identity,
            directory: directory
        )

        _ = try await cache.listUserTechniques()

        // A second repository over the same directory, which is what the next
        // launch is: the answer has to come off disk rather than out of a memo.
        let relaunched = CachedUserTechniqueRepository(
            caching: ScriptedServer(list([]), failing: true),
            identity: identity,
            directory: directory
        )
        let local = try #require(await relaunched.localUserTechniques())
        #expect(local.techniques.map(\.id) == ["a", "b"])
    }

    @Test("Nothing is served before a first fetch has ever succeeded")
    func nothingIsServedBeforeAFirstSuccess() async {
        let cache = CachedUserTechniqueRepository(
            caching: ScriptedServer(list(["a"]), failing: true),
            identity: mintingStore(holding: someone),
            directory: directory()
        )

        #expect(await cache.localUserTechniques() == nil)
    }

    /// The catalogue ships a seed and this deliberately does not: nobody else's
    /// exercises can stand in for somebody's own.
    @Test("Another person's snapshot is never served to this one")
    func anIdentitySwapIsNotServedTheOtherPersonsList() async throws {
        let directory = directory()
        let identity = mintingStore(holding: someone)
        let cache = CachedUserTechniqueRepository(
            caching: ScriptedServer(list(["mine"])),
            identity: identity,
            directory: directory
        )

        _ = try await cache.listUserTechniques()
        #expect(await cache.localUserTechniques() != nil)

        _ = identity.adopt(userId: somebodyElse)

        #expect(
            await cache.localUserTechniques() == nil,
            "a signed-in stranger must not inherit the previous person's exercises"
        )
    }

    @Test("A write patches the snapshot, so a cached list cannot outlive an edit")
    func aDeletePatchesTheSnapshot() async throws {
        let directory = directory()
        let identity = mintingStore(holding: someone)
        let cache = CachedUserTechniqueRepository(
            caching: ScriptedServer(list(["a", "b"])),
            identity: identity,
            directory: directory
        )

        _ = try await cache.listUserTechniques()
        try await cache.deleteUserTechnique(id: list(["a"]).techniques[0].id)

        let local = try #require(await cache.localUserTechniques())
        #expect(local.techniques.map(\.id) == ["b"])
    }

    /// The whole of the reported bug, at the level the screen reads.
    @MainActor
    @Test("A failed refresh leaves a drawn list standing")
    func aFailedRefreshKeepsTheList() async {
        let store = FakeStore(local: list(["kept"]))
        let model = UserTechniqueModel(store: store)

        await model.loadIfNeeded()
        await store.refuse(with: .transport(.stub()))
        await model.load()

        guard case let .loaded(shown) = model.state else {
            Issue.record("expected .loaded, got \(model.state)")
            return
        }
        #expect(shown.techniques.map(\.id) == ["kept"])
    }

    /// The other side of that rule: with nothing local, there is still a failure
    /// to report, because a silent empty section reads as "you wrote none".
    @MainActor
    @Test("A first load with nothing local and no server lands in .failed")
    func aFirstLoadWithNothingLocalFails() async {
        let store = FakeStore(refusing: .transport(.stub()))
        let model = UserTechniqueModel(store: store)

        await model.loadIfNeeded()

        guard case .failed = model.state else {
            Issue.record("expected .failed, got \(model.state)")
            return
        }
    }
}

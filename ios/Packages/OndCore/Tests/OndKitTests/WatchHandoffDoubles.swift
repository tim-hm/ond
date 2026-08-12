import Foundation
import OndKit
import os

/// The phone's identity, without a Keychain behind it. Mutable, so a test can
/// be the person who signs in between two foregrounds and has their id replaced
/// by the one their Apple account already had.
final class StubIdentity: UserIdentityStore {
    private let stored: OSAllocatedUnfairLock<UUID?>
    private let credential: OSAllocatedUnfairLock<String?>

    init(id: UUID?, credential: String? = nil) {
        stored = OSAllocatedUnfairLock(initialState: id)
        self.credential = OSAllocatedUnfairLock(initialState: credential)
    }

    func sessionCredential() -> String? {
        credential.withLock { $0 }
    }

    func adopt(sessionCredential value: String?) {
        credential.withLock { $0 = value }
    }

    func userId() -> UUID? {
        stored.withLock { $0 }
    }

    @discardableResult
    func adopt(_ id: UUID) -> Bool {
        stored.withLock { current in
            guard current != id else { return false }
            current = id
            return true
        }
    }
}

/// The system's launch call, answering whatever the test needs it to.
///
/// Shared by both models that place an order — the discreet handoff and the pulse
/// arrangement — because both take the same answer to mean the same thing: there
/// is no wrist coming, so retract what was placed for it.
final class ScriptedLauncher: WristLaunching {
    private let launches: Bool

    init(launches: Bool) {
        self.launches = launches
    }

    func prepare() async {}

    func launchWatchApp() async -> Bool {
        launches
    }
}

/// The rig both order-placing models are tested through: an outbox with an
/// identity behind it, and a count of how many times the radio was handed
/// something.
///
/// Shared because the observability trick is the interesting part and there is no
/// second way to do it: an order riding the context is only visible by asking the
/// outbox what it would hand over, and `handOver` is also what marks a context
/// delivered — so a test that reads twice sees nothing the second time unless
/// something changed in between. That is a property of the outbox worth knowing
/// once rather than rediscovering per suite.
@MainActor
final class PlacedOrders {
    let outbox: WatchHandoffOutbox
    private(set) var pushes = 0

    /// Subscribed by default, because sending the phone's errands to the wrist
    /// is what önd+ buys and neither of these suites is about the gate: without
    /// it every test here would be asserting against a refusal. The free case is
    /// pinned by its own tests, which pass `.free` deliberately.
    init(tier: SubscriptionTier = .plus) {
        outbox = WatchHandoffOutbox(
            identity: StubIdentity(id: UUID()),
            scores: StubScores(),
            entitledTier: { tier }
        )
    }

    /// What a model's `push` closure should be wired to.
    func pushed() {
        pushes += 1
    }

    /// What the outbox would hand the radio right now — nil when no order is
    /// riding, which is how a retraction is observable from outside.
    func riding() async -> WatchSessionOrder? {
        var handed: WatchSessionOrder?
        await outbox.handOver { handed = $0.order }
        return handed
    }
}

/// Controlled-pause history, without a file behind it. Mutable so a test can be
/// the person who takes their first BOLT test between two foregrounds.
final class StubScores: BoltScoreRecording {
    private let stored = OSAllocatedUnfairLock<[BoltScore]>(initialState: [])

    init(seconds: [Int] = []) {
        stored.withLock { $0 = seconds.map { BoltScore(seconds: $0) } }
    }

    func record(_ score: BoltScore) async {
        stored.withLock { $0.append(score) }
    }

    func recordedScores() async -> [BoltScore] {
        stored.withLock { $0 }
    }
}

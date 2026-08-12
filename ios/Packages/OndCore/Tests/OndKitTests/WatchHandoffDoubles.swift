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

    func launchWatchApp() async -> Bool {
        launches
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

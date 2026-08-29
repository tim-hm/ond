import Foundation
@testable import OndKit
import Testing

/// Keeps what it was handed, so a test can tell "recorded" from "discarded"
/// and prove a removal or a merge reached the store underneath. Main-actor
/// rather than an actor, unlike `SessionSpy` below, so `settle`'s
/// synchronous condition can read `recorded` without a hop — the reason
/// three private near-copies of this once existed.
@MainActor
final class CapturingRecorder: SessionRecording {
    private(set) var recorded: [SessionRecord] = []
    private(set) var removed: [SessionRecord.ID] = []

    func record(_ session: SessionRecord) async {
        recorded.append(session)
    }

    func recordedSessions() async -> [SessionRecord] {
        recorded
    }

    func remove(_ id: SessionRecord.ID) async {
        removed.append(id)
    }

    func merge(_ sessions: [SessionRecord]) async -> Bool {
        recorded.append(contentsOf: sessions)
        return !sessions.isEmpty
    }
}

/// Records and tombstones together, the way `FileSessionStore` does — the
/// two seams are separate protocols and one store answers both. A file of
/// its own for the reason `ServerSpy` has one: the doubles and factories
/// came to more than half of `SessionSyncQueueTests`, which is what put
/// that file over `file_length`.
actor SessionSpy: SessionRecording, TombstoneStoring {
    private(set) var stored: [SessionRecord]
    private(set) var tombstoned: [SessionRecord.ID] = []

    init(_ stored: [SessionRecord] = []) {
        self.stored = stored
    }

    func record(_ session: SessionRecord) async {
        stored.append(session)
    }

    func remove(_ id: SessionRecord.ID) async {
        guard stored.contains(where: { $0.id == id }) else { return }
        stored.removeAll { $0.id == id }
        tombstoned.append(id)
    }

    func tombstonedSessions() async -> [SessionRecord.ID] {
        tombstoned
    }

    func forgetTombstones(_ ids: [SessionRecord.ID]) async {
        let forgotten = Set(ids)
        tombstoned.removeAll { forgotten.contains($0) }
    }

    func recordedSessions() async -> [SessionRecord] {
        stored
    }

    func merge(_ sessions: [SessionRecord]) async -> Bool {
        let known = Set(stored.map(\.id))
        let missing = sessions.filter { !known.contains($0.id) }
        stored.append(contentsOf: missing)
        return !missing.isEmpty
    }

    func erase() async {
        stored = []
        tombstoned = []
    }
}

actor ScoreSpy: BoltScoreRecording {
    private(set) var stored: [BoltScore]

    init(_ stored: [BoltScore] = []) {
        self.stored = stored
    }

    func record(_ score: BoltScore) async {
        stored.append(score)
    }

    func recordedScores() async -> [BoltScore] {
        stored
    }
}

actor RateSpy: RestingRateRecording {
    private(set) var stored: [RestingRate]

    init(_ stored: [RestingRate] = []) {
        self.stored = stored
    }

    func record(_ rate: RestingRate) async {
        stored.append(rate)
    }

    func recordedRates() async -> [RestingRate] {
        stored
    }
}

/// A queue over the three stores a practice lives in, each defaulting to an empty
/// spy. Here rather than written out per test: the queue gained a third store to
/// drain and every construction grew a line for it, which took the suite past
/// `type_body_length`. Naming only the store a test is about is also what makes
/// each one read as the state it is describing.
func syncQueue(
    sessions: any SessionRecording = SessionSpy(),
    scores: any BoltScoreRecording = ScoreSpy(),
    rates: any RestingRateRecording = RateSpy(),
    journeys: any JourneySyncing,
    tombstones: (any TombstoneStoring)? = nil,
    ledger: SyncLedger
) -> SessionSyncQueue {
    SessionSyncQueue(
        sessions: sessions,
        scores: scores,
        rates: rates,
        journeys: journeys,
        tombstones: tombstones,
        ledger: ledger
    )
}

/// A defaults suite of its own, so tests neither see each other's ledger nor
/// leave one behind on the machine that ran them.
func syncDefaults() -> UserDefaults {
    let name = "journey-sync-tests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: name) else {
        Issue.record("a defaults suite is available")
        return .standard
    }
    defaults.removePersistentDomain(forName: name)
    return defaults
}

func syncSession(_ offsetHours: Int) -> SessionRecord {
    SessionRecord(
        techniqueSlug: "box-breathing",
        startedAt: Date(timeIntervalSince1970: 1_777_000_000)
            .addingTimeInterval(TimeInterval(offsetHours) * 3600),
        duration: .seconds(120),
        cyclesCompleted: 4,
        breathCount: 8,
        completed: true
    )
}

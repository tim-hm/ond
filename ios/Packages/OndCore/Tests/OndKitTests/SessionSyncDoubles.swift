import Foundation
@testable import OndKit
import Testing

/// Records and tombstones together, the way `FileSessionStore` does — the two
/// seams are separate protocols and one store answers both.
///
/// A file of its own for the reason `ServerSpy` has one: the doubles and
/// factories came to more than half of `SessionSyncQueueTests`, which is what
/// put that file over `file_length`.
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

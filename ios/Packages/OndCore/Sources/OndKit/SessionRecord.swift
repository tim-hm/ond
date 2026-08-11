import Foundation

/// One session a person actually did.
///
/// Recorded locally from the first session onwards, before there is any account
/// to attach it to. The field set is deliberately the one the future
/// `RecordSessions` RPC takes — including `id`, which is the idempotency key a
/// sync can retry against — so syncing later is a mapping rather than a
/// migration of everything already on disk.
public struct SessionRecord: Sendable, Codable, Equatable, Identifiable {
    public let id: UUID
    public let techniqueSlug: String
    public let startedAt: Date
    /// Milliseconds rather than a `Duration`, because this shape is written to
    /// disk: milliseconds are what the proto carries and what a person reading
    /// the file can understand, where an encoded `Duration` is a pair of opaque
    /// integers.
    public let durationMs: Int
    /// Cycles wholly finished. A session ended mid-cycle counts the cycles
    /// behind it, never the one it was in.
    public let cyclesCompleted: Int
    /// Inhales taken — two per cycle in techniques like the physiological sigh.
    public let breathCount: Int
    /// Whether the timeline ran out, as opposed to the person ending it early.
    /// Both are recorded; only this distinguishes them.
    public let completed: Bool
    /// The occasion that prescribed the session, nil when the person picked
    /// the technique themselves.
    public let occasionSlug: String?
    /// How the session was delivered. Carried because `completed` reads
    /// differently per surface: a discreet session's sparse cadence runs near
    /// half an hour, and grading it like a five-minute guided session would
    /// misread both.
    public let surface: DeliverySurface

    public init(
        id: UUID = UUID(),
        techniqueSlug: String,
        startedAt: Date,
        duration: Duration,
        cyclesCompleted: Int,
        breathCount: Int,
        completed: Bool,
        occasionSlug: String? = nil,
        surface: DeliverySurface = .fullScreen
    ) {
        self.id = id
        self.techniqueSlug = techniqueSlug
        self.startedAt = startedAt
        durationMs = Int(duration.milliseconds)
        self.cyclesCompleted = cyclesCompleted
        self.breathCount = breathCount
        self.completed = completed
        self.occasionSlug = occasionSlug
        self.surface = surface
    }

    /// Backwards-compatible with every `sessions.json` written before the two
    /// provenance fields existed: absent reads as no occasion and full-screen,
    /// which was the only surface any build could deliver then.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        techniqueSlug = try container.decode(String.self, forKey: .techniqueSlug)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        durationMs = try container.decode(Int.self, forKey: .durationMs)
        cyclesCompleted = try container.decode(Int.self, forKey: .cyclesCompleted)
        breathCount = try container.decode(Int.self, forKey: .breathCount)
        completed = try container.decode(Bool.self, forKey: .completed)
        occasionSlug = try container.decodeIfPresent(String.self, forKey: .occasionSlug)
        surface = try container.decodeIfPresent(DeliverySurface.self, forKey: .surface)
            ?? .fullScreen
    }

    public var duration: Duration {
        .milliseconds(durationMs)
    }

    /// A session ended by hand inside this window never reaches a store: it is
    /// a false start — a mistap, a phone call — not practice, and a journal of
    /// two-second entries teaches people to stop trusting the journal.
    /// Completed sessions are exempt; finishing a plan is practice however
    /// short the plan was.
    public static let minimumRecordedDuration: Duration = .seconds(10)

    /// Whether this record is a false start rather than practice.
    ///
    /// On the record rather than on either session model, because it is a fact
    /// about what was recorded and both models — the guided session and the
    /// discreet cadence — gate their recording on the same rule. Two copies
    /// would drift the day the threshold moves.
    public var isFalseStart: Bool {
        !completed && duration < Self.minimumRecordedDuration
    }

    /// What a summary leads with.
    ///
    /// Here rather than in either summary screen because the product's copy
    /// rule is a rule: celebrate what happened, never grade it. Two views of
    /// the same session — one in the hand, one on the wrist — saying different
    /// things about it is exactly the drift that turns a rule into a habit
    /// somebody remembered.
    /// One line for every unfinished session, whatever it finished: the breath
    /// is the unit the person felt, the cycle is the plan's, and a headline
    /// that switched units by how far they got would be a grade wearing a
    /// celebration's words.
    public var headline: String {
        completed ? "Nicely done." : "Every breath counts"
    }

    /// "cycle" or "cycles", for the count beside it.
    public var cyclesLabel: String {
        cyclesCompleted == 1 ? "cycle" : "cycles"
    }

    /// "breath" or "breaths", for the count beside it.
    public var breathsLabel: String {
        breathCount == 1 ? "breath" : "breaths"
    }
}

/// Somewhere to keep finished sessions until there is a server to send them to.
///
/// Non-throwing on purpose: a failed local write is nothing the person mid-way
/// through a breathing session can act on, and nothing a caller can retry
/// meaningfully. Implementations log and carry on.
public protocol SessionRecording: Sendable {
    func record(_ session: SessionRecord) async
    /// Every recorded session, oldest first.
    func recordedSessions() async -> [SessionRecord]
    /// Forgets a session for good: it leaves the list, the stats, and — via a
    /// tombstone — stays gone through every later `merge`. The server's copy,
    /// if one was synced, outlives this; see `FileSessionStore.remove`.
    func remove(_ id: SessionRecord.ID) async
    /// Adds sessions this device does not hold, matching on `id`. The restore
    /// path: the identity survives a reinstall, so the server can hold history
    /// this file has lost.
    ///
    /// - Returns: whether anything new was added. The answer to "did local
    ///   state change", which is what decides whether a screen re-reads it —
    ///   the server holding sessions it already sent us is the common case,
    ///   and it changes nothing.
    func merge(_ sessions: [SessionRecord]) async -> Bool
}

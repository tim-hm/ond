import Foundation

/// One session a person actually did. Recorded locally before there is any
/// account to attach it to. The field set matches the future `RecordSessions`
/// RPC — including `id`, the idempotency key a sync can retry against — so
/// syncing later is a mapping, not a migration of what is already on disk.
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

    /// Whether this record is a false start rather than practice. On the
    /// record because both session models gate their recording on this same
    /// rule; two copies would drift the day the threshold moves.
    public var isFalseStart: Bool {
        !completed && duration < Self.minimumRecordedDuration
    }

    /// What a summary leads with. Here, not in either summary screen, so the
    /// copy rule — celebrate, never grade — reads the same on the phone and
    /// on the watch. Every unfinished session gets the one line: a headline
    /// that changed with progress would grade the session.
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
    /// path: identity survives a reinstall, so the server can hold history
    /// this file has lost.
    /// - Returns: whether anything new was added, which decides whether a
    ///   screen re-reads local state; known sessions re-sent change nothing.
    func merge(_ sessions: [SessionRecord]) async -> Bool
}

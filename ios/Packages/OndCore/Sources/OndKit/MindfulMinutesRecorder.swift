import Foundation

/// The session store each screen records through, with one addition: every
/// session it keeps is also credited to Health as Mindful Minutes — unless the
/// person has switched the write off in Settings.
///
/// A wrapper rather than a change to `FileSessionStore`, because only *new*
/// practice earns minutes: the sync queue and the restore path work on the bare
/// store underneath, so history arriving from the server — possibly written to
/// Health already, by the device that breathed it — never writes again. And
/// only `record` writes here: the store's own discard rule has already thrown
/// out the mistaps, and minutes actually breathed count whether or not the
/// plan ran out.
///
/// The write is governed twice: by the in-app preference below, on by default,
/// and by Health's own permission sheet, which still has the last word. The
/// preference exists for whoever wants to practise without crediting Health at
/// all — the mirror of `HealthContextModel.coachReadsHealthTrends` on the read
/// side, and stored the same way, because "who writes to Health" must no more
/// reach the server than "who reads from it".
public struct MindfulMinutesRecorder: SessionRecording {
    /// Where the in-app preference is stored. Shared with `HealthContextModel`,
    /// which owns the switch the settings screen binds to.
    public static let preferenceKey = "health.writesMindfulMinutes"

    /// The stored preference, read from `defaults`. An absent key reads as
    /// true — the write is on until somebody switches it off.
    public static func writesToHealth(in defaults: UserDefaults) -> Bool {
        defaults.flag(forKey: preferenceKey, default: true)
    }

    private let store: any SessionRecording
    private let health: any HealthStore
    // SAFETY: UserDefaults is not marked Sendable but is documented
    // thread-safe ("The UserDefaults class is thread-safe."), and this
    // reference is only ever read from.
    private nonisolated(unsafe) let defaults: UserDefaults

    public init(
        wrapping store: any SessionRecording,
        health: any HealthStore,
        defaults: UserDefaults = .standard
    ) {
        self.store = store
        self.health = health
        self.defaults = defaults
    }

    public func record(_ session: SessionRecord) async {
        await store.record(session)

        // A discreet session earns no Mindful Minutes: its half hour is mostly
        // deliberate silence around a few minutes of breathing, and a single
        // Health sample has no way to say so — a ~29-minute credit for thirty
        // breaths would outweigh a whole guided session several times over.
        // Better no claim than a false one; the journal still keeps the
        // session itself, surface and all.
        guard session.surface != .discreet else { return }

        // Read per session rather than held from init, so flipping the switch
        // takes effect on the next practice, not the next launch.
        guard Self.writesToHealth(in: defaults) else { return }

        await health.writeMindfulSession(
            from: session.startedAt,
            to: session.startedAt.addingTimeInterval(session.duration.seconds)
        )
    }

    public func recordedSessions() async -> [SessionRecord] {
        await store.recordedSessions()
    }

    public func remove(_ id: SessionRecord.ID) async {
        await store.remove(id)
    }

    public func merge(_ sessions: [SessionRecord]) async -> Bool {
        await store.merge(sessions)
    }
}

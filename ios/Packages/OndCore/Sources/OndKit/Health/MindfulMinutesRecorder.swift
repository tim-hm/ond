import Foundation

/// The session store each screen records through. It also credits each kept
/// session to Health as Mindful Minutes. A wrapper, so the sync queue and the
/// restore path use the bare store: only new practice earns minutes, never
/// history that arrives from the server. The write needs the local preference
/// below and Health's own permission sheet.
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

        // A discreet session earns no Mindful Minutes. Its half hour is mostly
        // silence around a few minutes of breathing, and one Health sample
        // cannot say so. The journal still keeps the session.
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

import Foundation
@testable import OndKit
import Testing

/// The write-back's promises: every session a screen records is credited to
/// Health over exactly the span it was breathed — unless the in-app switch is
/// off — and nothing else — not a restore, not a removal — ever writes there.
@Suite("Mindful Minutes write-back")
@MainActor
struct MindfulMinutesRecorderTests {
    private static let startedAt = Date(timeIntervalSince1970: 1_777_000_000)

    // Fresh per test: Swift Testing builds a new suite value for each one.
    // The defaults suite is fresh too, so the preference starts absent — the
    // state every install begins in — and the host machine's own defaults
    // can't leak a switched-off write into a test.
    private let store = CapturingRecorder()
    private let health = SpyHealthStore()
    private let defaults: UserDefaults
    private let recorder: MindfulMinutesRecorder

    init() throws {
        defaults =
            try #require(UserDefaults(suiteName: "mindful-minutes-tests.\(UUID().uuidString)"))
        recorder = MindfulMinutesRecorder(wrapping: store, health: health, defaults: defaults)
    }

    private func session(minutes: Int = 5) -> SessionRecord {
        SessionRecord(
            techniqueSlug: "box-breathing",
            startedAt: Self.startedAt,
            duration: .seconds(minutes * 60),
            cyclesCompleted: 10,
            breathCount: 10,
            completed: true
        )
    }

    /// Also the default-on proof: the suite's defaults hold no preference at
    /// all, which is every install before the switch is ever touched.
    ///
    /// No authorization call to assert before the write: the store asks for its
    /// own grant, so there is no ordering left for a caller to get wrong — see
    /// `HealthStore`.
    @Test("A recorded session credits exactly the span it was breathed")
    func recordWritesToHealth() async {
        let session = session(minutes: 5)
        await recorder.record(session)

        #expect(store.recorded == [session])
        #expect(await health.calls == [
            .wroteMindfulSession(
                start: Self.startedAt,
                end: Self.startedAt.addingTimeInterval(5 * 60)
            ),
        ])
    }

    @Test("Switched off, a kept session stays out of Health entirely")
    func switchedOffWritesNothing() async {
        defaults.set(false, forKey: MindfulMinutesRecorder.preferenceKey)
        let session = session()

        await recorder.record(session)

        #expect(store.recorded == [session], "the session itself is still kept")
        #expect(await health.calls.isEmpty, "Health is not touched at all")
    }

    /// The switch is read per session, not held from init — flipping it must
    /// not wait for a relaunch.
    @Test("Flipping the switch takes effect on the next session")
    func flippingTheSwitchTakesEffectImmediately() async {
        defaults.set(false, forKey: MindfulMinutesRecorder.preferenceKey)
        await recorder.record(session())
        #expect(await health.calls.isEmpty)

        defaults.set(true, forKey: MindfulMinutesRecorder.preferenceKey)
        await recorder.record(session())

        #expect(await health.calls.count == 1, "the write happened this time")
    }

    /// A discreet half hour is mostly silence; one continuous Health sample
    /// cannot say so, and a false 29-minute credit is worse than none.
    @Test("A discreet session is kept but never credited to Health")
    func discreetStaysOutOfHealth() async {
        let session = SessionRecord(
            techniqueSlug: "coherent-breathing",
            startedAt: Self.startedAt,
            duration: .seconds(29 * 60),
            cyclesCompleted: 30,
            breathCount: 30,
            completed: true,
            occasionSlug: "through-this-meeting",
            surface: .discreet
        )

        await recorder.record(session)

        #expect(store.recorded == [session], "the journal keeps it")
        #expect(await health.calls.isEmpty, "Health hears nothing")
    }

    @Test("Restored history is not new practice — a merge writes nothing")
    func mergeStaysOutOfHealth() async {
        let added = await recorder.merge([session()])

        #expect(added)
        #expect(store.recorded.count == 1)
        #expect(await health.calls.isEmpty)
    }

    @Test("Reads and removals pass straight through, touching Health never")
    func forwarding() async {
        let session = session()
        await store.record(session)

        #expect(await recorder.recordedSessions() == [session])
        await recorder.remove(session.id)
        #expect(store.removed == [session.id])
        #expect(await health.calls.isEmpty)
    }
}

import Foundation
@testable import OndKit
import Testing

/// What the spy below remembers. At file scope only because the lint rule
/// caps type nesting one level short of where this naturally lives.
private enum HealthCall: Equatable {
    case requestedRead
    case requestedWrite
    case wroteMindfulSession(start: Date, end: Date)
    case wroteMood(Mood, at: Date)
}

/// The write-back's promises: every session a screen records is credited to
/// Health over exactly the span it was breathed — unless the in-app switch is
/// off — and nothing else — not a restore, not a removal — ever writes there.
@Suite("Mindful Minutes write-back")
@MainActor
struct MindfulMinutesRecorderTests {
    /// Remembers every call in order, so a test can assert that authorization
    /// was asked before the write — and that nothing was asked at all.
    private actor SpyHealthStore: HealthStore {
        private(set) var calls: [HealthCall] = []

        func requestReadAuthorization() async {
            calls.append(.requestedRead)
        }

        func requestWriteAuthorization() async {
            calls.append(.requestedWrite)
        }

        func restingHeartRate(from _: Date, to _: Date) async -> [DailyQuantity] {
            []
        }

        func heartRateVariability(from _: Date, to _: Date) async -> [DailyQuantity] {
            []
        }

        func respiratoryRate(from _: Date, to _: Date) async -> [DailyQuantity] {
            []
        }

        func writeMindfulSession(from start: Date, to end: Date) async {
            calls.append(.wroteMindfulSession(start: start, end: end))
        }

        /// Recorded like the rest, so a test asserting an empty call list is
        /// asserting that Health heard nothing at all — not merely that no
        /// minutes were credited.
        func writeMood(_ mood: Mood, at date: Date) async {
            calls.append(.wroteMood(mood, at: date))
        }
    }

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
    @Test("A recorded session asks for write access, then credits its span")
    func recordWritesToHealth() async {
        let session = session(minutes: 5)
        await recorder.record(session)

        #expect(store.recorded == [session])
        #expect(await health.calls == [
            .requestedWrite,
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
        #expect(await health.calls.isEmpty, "not even authorization is asked for")
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

        #expect(await health.calls.count == 2, "authorization and the write both happened")
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
        #expect(await health.calls.isEmpty, "Health hears nothing, not even authorization")
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

import Foundation
@testable import OndKit
import Testing

/// The cadence's contract: bursts fall where `DiscreetCadence.burstStarts`
/// says, silence between them delivers nothing, and the record kept is the
/// practice actually delivered — stamped with the occasion and the surface,
/// which is what the whole provenance column exists for.
@MainActor
struct DiscreetSessionModelTests {
    /// A session over `briefBreathing`: each burst is six 60 ms cycles, so a
    /// whole burst is 360 ms and the cadence's minutes are all gap.
    private func model(
        clock: ManualClock,
        cues: RecordingCues,
        recorder: any SessionRecording = DiscardingRecorder()
    ) -> DiscreetSessionModel {
        DiscreetSessionModel(
            technique: briefBreathing(),
            occasionSlug: "through-this-meeting",
            cues: cues,
            recorder: recorder,
            clock: clock
        )
    }

    @Test func theBurstsFallWhereTheCadenceSays() async throws {
        let clock = ManualClock()
        let cues = RecordingCues()
        let model = model(clock: clock, cues: cues)

        model.start()
        clock.advance(by: .milliseconds(360))
        try await settle { cues.played.count == 12 }
        #expect(model.burstsBegun == 1, "the opening burst begins at t = 0")

        // Just short of the second burst: the first gap is three minutes, and
        // nothing may fire inside it.
        clock.advance(by: .seconds(179))
        try await settle { model.status == .running }
        #expect(cues.played.count == 12, "the gap delivers nothing")
        #expect(model.burstsBegun == 1)

        clock.advance(by: .seconds(1) + .milliseconds(360))
        try await settle { cues.played.count == 24 }
        #expect(model.burstsBegun == 2, "the second burst begins after the gap")
    }

    @Test func anEarlyEndRecordsTheBurstsDelivered() async throws {
        let clock = ManualClock()
        let cues = RecordingCues()
        let model = model(clock: clock, cues: cues)

        model.start()
        clock.advance(by: .milliseconds(360))
        try await settle { cues.played.count == 12 }

        // A minute into the first silence, the meeting ends and so does the
        // session.
        clock.advance(by: .seconds(60))
        model.end()

        let record = try #require(model.record)
        #expect(!record.completed)
        #expect(record.cyclesCompleted == 6, "one burst's cycles, none from the silence")
        #expect(record.breathCount == 6)
        #expect(record.occasionSlug == "through-this-meeting")
        #expect(record.surface == .discreet)
        #expect(cues.completions == 0, "an ended session earns no completion cue")
        #expect(cues.stops == 1)

        let frozen = model.elapsed
        clock.advance(by: .seconds(10))
        #expect(model.elapsed == frozen, "a finished session's clock is stopped")
    }

    /// End landing inside the closing purr — after the last cue, before the
    /// cadence's own finish — must not let the loop finish the session a
    /// second time: the second record would carry a fresh idempotency key,
    /// and the server would count the session twice.
    @Test func anEndDuringTheClosingPurrRecordsExactlyOnce() async throws {
        let clock = ManualClock()
        let cues = RecordingCues()
        let store = CapturingRecorder()
        let model = model(clock: clock, cues: cues, recorder: store)

        model.start()
        // Every burst has fired; the loop is waiting out the last beat's purr.
        clock.advance(by: DiscreetCadence.gaps.reduce(.zero, +) + .milliseconds(350))
        try await settle { cues.played.count == 60 }
        #expect(model.status == .running, "the closing purr is still playing")

        model.end()
        #expect(model.record?.completed == false)

        // Let the cancelled loop run its course; it must find nothing to do.
        clock.advance(by: .seconds(1))
        try await settle { store.recorded.count == 1 }
        try await Task.sleep(for: .milliseconds(50))
        #expect(store.recorded.count == 1, "the loop's own finish records no second session")
        #expect(model.record?.completed == false, "and does not rewrite the record as completed")
        #expect(cues.completions == 0)
    }

    @Test func theWholeCadenceCompletesAndRecordsItself() async throws {
        let clock = ManualClock()
        let cues = RecordingCues()
        let store = CapturingRecorder()
        let model = model(clock: clock, cues: cues, recorder: store)

        model.start()
        clock.advance(by: DiscreetCadence.gaps.reduce(.zero, +) + .seconds(1))
        try await settle { model.status == .finished }

        let record = try #require(model.record)
        #expect(record.completed)
        #expect(record.cyclesCompleted == 30, "five bursts of six cycles")
        #expect(record.breathCount == 30)
        #expect(record.surface == .discreet)
        #expect(cues.completions == 1)

        try await settle { store.recorded.count == 1 }
        #expect(store.recorded.first == record)
    }

    @Test func aFalseStartIsLetGo() async throws {
        let clock = ManualClock()
        let cues = RecordingCues()
        let store = CapturingRecorder()
        let model = model(clock: clock, cues: cues, recorder: store)

        model.start()
        clock.advance(by: .seconds(5))
        model.end()

        #expect(model.wasDiscarded, "five seconds is a mistap, not practice")
        // Give an erroneous record every chance to arrive before asserting
        // it never does.
        try await Task.sleep(for: .milliseconds(50))
        #expect(store.recorded.isEmpty, "a discarded session never reaches the store")
    }
}

import Foundation
@testable import OndKit
import Testing

/// The open-ended retention, the one place the session's two clocks come apart:
/// the plan stops at the top of the hold while the person's time runs on. On a
/// `ManualClock` with equality assertions — as bounds they failed one run in
/// eight, a late wake-up stepping over a 30 ms phase. The hold's nominal minute
/// keeps a plan-time reading and a wall-clock reading impossible to confuse.
@MainActor
@Suite("Ending a hold the clock cannot")
struct SessionHoldTests {
    private static let retention = Technique(
        id: "id",
        slug: "wim-hof-rounds",
        name: "Wim Hof-style Rounds",
        summary: "",
        goal: .energy,
        stages: [
            Stage(
                phases: [Phase(kind: .holdOut, duration: .milliseconds(60000))],
                cycles: 1,
                openEnded: true
            ),
            Stage(phases: [Phase(kind: .inhale, duration: .milliseconds(100))], cycles: 1),
        ],
        recommendedRounds: 1
    )

    /// A retention with a stage on each side — breathe, hold, recover — the shape
    /// a Wim Hof round has and `retention` does not: that fixture opens on the
    /// hold, so nothing there says the plan resumes into a *following stage*
    /// rather than the next beat of the same one. The short breathing makes a
    /// plan position read as obviously not a hold; the minute as above.
    private static let sequence = Technique(
        id: "id",
        slug: "wim-hof-rounds",
        name: "Wim Hof-style Rounds",
        summary: "",
        goal: .energy,
        stages: [
            Stage(
                phases: [
                    Phase(kind: .inhale, duration: .milliseconds(30)),
                    Phase(kind: .exhale, duration: .milliseconds(30)),
                ],
                cycles: 1
            ),
            Stage(
                phases: [Phase(kind: .holdOut, duration: .milliseconds(60000))],
                cycles: 1,
                openEnded: true
            ),
            Stage(phases: [Phase(kind: .holdIn, duration: .milliseconds(30))], cycles: 1),
        ],
        recommendedRounds: 1
    )

    /// A session on the fixture that opens in its hold, already in it.
    ///
    /// The clock belongs to the caller because driving it is the test; the cues
    /// default away, since only two of these assert on what was played.
    private func startedSession(
        cues: RecordingCues = RecordingCues(),
        on clock: ManualClock
    ) async throws -> SessionModel {
        let model = SessionModel(
            technique: Self.retention,
            cues: cues,
            recorder: DiscardingRecorder(),
            clock: clock
        )
        model.start()
        try await waitFor("the hold to begin") { model.status == .holding }
        return model
    }

    @Test("The plan stops inside a hold while the person's own time does not")
    func stopsThePlanForAHold() async throws {
        let cues = RecordingCues()
        let clock = ManualClock()
        let model = try await startedSession(cues: cues, on: clock)

        #expect(model.elapsed == .zero, "the plan is pinned to the top of the hold")
        #expect(cues.played.count == 1, "the hold is cued once, on entry")

        clock.advance(by: .milliseconds(60))

        #expect(model.elapsed == .zero, "the plan has still not moved")
        #expect(model.realElapsed == .milliseconds(60), "but the person has been holding")
        #expect(model.holdElapsed == .milliseconds(60))
        #expect(model.status == .holding)
    }

    /// The plan resumes at the *end* of the hold's beat, however long the hold
    /// took — a short retention must not skip the recovery breath, and a long
    /// one must not eat it.
    @Test("Releasing a hold splices the plan back on at the hold's end")
    func splicesThePlanOnRelease() async throws {
        let clock = ManualClock()
        let model = try await startedSession(on: clock)
        clock.advance(by: .milliseconds(30))

        model.release()

        #expect(model.status == .running)
        #expect(model.elapsed == .milliseconds(60000), "the plan jumped the whole hold")
        #expect(model.holdElapsed == .zero)

        try await waitFor("the breath after the hold") { model.currentBeat?.stage == 1 }
        clock.advance(by: .milliseconds(100))
        try await waitFor("the session to finish") { model.status == .finished }

        let record = try #require(model.record)
        #expect(record.completed)
        #expect(record.cyclesCompleted == 2)
        // The plan is a minute long and this session was not. The recorded
        // duration is wall-clock, so the nominal hold cannot leak into it.
        #expect(
            record.duration == .milliseconds(130),
            "thirty held, and the hundred-millisecond breath the release handed back"
        )
    }

    /// A pause inside a hold is not the end of the hold. Resuming has to land
    /// back in it — anywhere else and the person loses a retention they were
    /// still in — and the hold's own timer has to pick up where it stopped.
    @Test("A pause inside a hold resumes into the same hold")
    func resumesIntoTheHold() async throws {
        let cues = RecordingCues()
        let clock = ManualClock()
        let model = try await startedSession(cues: cues, on: clock)
        clock.advance(by: .milliseconds(30))

        model.pause()
        #expect(model.status == .paused)
        #expect(model.holdElapsed == .milliseconds(30))

        clock.advance(by: .milliseconds(40))
        #expect(model.holdElapsed == .milliseconds(30), "a paused hold does not count time")

        model.resume()
        #expect(model.status == .holding)
        #expect(
            model.holdElapsed == .milliseconds(30),
            "the hold's timer carried on from where it stopped"
        )
        #expect(model.elapsed == .zero, "and the plan is still pinned")
        #expect(cues.played.count == 1, "resuming mid-hold does not re-cue it")
    }

    /// The clause chaining stages must not break: a hold ended partway through a
    /// sequence stops the plan where it stands and hands the rest back on
    /// release. Nothing about the hold is special-cased on position, and this
    /// keeps it that way — a wrong resume offset would skip or repeat the
    /// recovery stage, the part the hold exists to be followed by.
    @Test("A hold partway through a sequence stops the clock and hands the rest back")
    func holdsInsideASequence() async throws {
        let cues = RecordingCues()
        let clock = ManualClock()
        let model = SessionModel(
            technique: Self.sequence,
            cues: cues,
            recorder: DiscardingRecorder(),
            clock: clock
        )

        // One boundary at a time, waiting for each: the clock stops exactly on
        // a beat's end, so the loop cannot step over the beat that follows.
        model.start()
        try await waitFor("the first breath") { model.currentBeat?.phase == 0 }
        clock.advance(by: .milliseconds(30))
        try await waitFor("the breath out") { model.currentBeat?.phase == 1 }
        clock.advance(by: .milliseconds(30))
        try await waitFor("the hold to begin") { model.status == .holding }

        let held = try #require(model.currentBeat)
        #expect(held.stage == 1, "the hold is the second of three stages")
        #expect(
            model.elapsed == .milliseconds(60),
            "the plan is pinned at the top of the hold, not at zero"
        )

        clock.advance(by: .milliseconds(40))
        #expect(model.elapsed == .milliseconds(60), "and it has not moved")
        #expect(model.realElapsed == .milliseconds(100), "while the person has been holding")

        model.release()

        #expect(model.status == .running)
        #expect(
            model.elapsed == .milliseconds(60060),
            "the plan jumped the whole hold and landed in the stage after it"
        )

        try await waitFor("the stage after the hold") { model.currentBeat?.stage == 2 }
        clock.advance(by: .milliseconds(30))
        try await waitFor("the session to finish") { model.status == .finished }

        #expect(
            cues.played.map(\.stage) == [0, 0, 1, 2],
            "both opening breaths, the hold once on entry, then the stage after it"
        )

        let record = try #require(model.record)
        #expect(record.completed)
        #expect(record.cyclesCompleted == 3, "one cycle from each stage")
        // The plan is a minute long and this session was not.
        #expect(record.duration == .milliseconds(130), "sixty breathing, forty held, thirty after")
    }

    /// Ending a session mid-hold records what happened rather than what was
    /// planned: the hold was entered but never finished, so its cycle is not one
    /// the person is told they completed.
    @Test("Ending inside a hold records the hold as unfinished")
    func endsInsideAHold() async throws {
        let clock = ManualClock()
        let model = try await startedSession(on: clock)
        clock.advance(by: .milliseconds(20))

        model.end()

        let record = try #require(model.record)
        #expect(!record.completed)
        #expect(record.cyclesCompleted == 0)
        #expect(record.duration == .milliseconds(20), "what they held, not what was planned")
    }
}

/// Two 30 ms breaths, so a session runs out inside a test rather than inside a
/// technique. `cycles` is how the same fixture serves both a run that finishes
/// and one that cannot: a thousand cycles outlives any test that ends it by hand.
@MainActor
func briefBreathing(cycles: Int = 1) -> Technique {
    Technique(
        id: "id",
        slug: "box-breathing",
        name: "Box Breathing",
        summary: "",
        goal: .calm,
        stages: [
            Stage(
                phases: [
                    Phase(kind: .inhale, duration: .milliseconds(30)),
                    Phase(kind: .exhale, duration: .milliseconds(30)),
                ],
                cycles: cycles
            ),
        ],
        recommendedRounds: 1
    )
}

/// Remembers what it was asked to play, so a test can assert a beat was cued
/// once rather than on every turn of the loop.
@MainActor
final class RecordingCues: SessionCueing {
    private(set) var played: [SessionTimeline.Beat] = []
    /// The beats whose line was started early, in the gap before their
    /// boundary. Kept apart from `played`: the two happen at different
    /// instants, and the point of the lead is the distance between them.
    private(set) var spokenAhead: [SessionTimeline.Beat] = []
    private(set) var completions = 0
    /// Counted, not just flagged: the hardware is released from two places and
    /// the interesting failure is both of them firing.
    private(set) var stops = 0

    /// Defaulted to the answer that makes a departure stop the session, because
    /// that is the behaviour every suite here predates. Only the background
    /// suite passes the other one.
    let playsInBackground: Bool

    init(playsInBackground: Bool = false) {
        self.playsInBackground = playsInBackground
    }

    /// Counted rather than flagged for the same reason `stops` is: what the
    /// background suite asserts is that a pause hands the runtime back exactly
    /// once and a resume takes it again, not merely that both were mentioned.
    private(set) var pauses = 0
    private(set) var resumes = 0

    func prepare() {}

    func pause() {
        pauses += 1
    }

    func resume() {
        resumes += 1
    }

    func play(_ beat: SessionTimeline.Beat) {
        played.append(beat)
    }

    func speakAhead(_ beat: SessionTimeline.Beat) {
        spokenAhead.append(beat)
    }

    func playCompletion() {
        completions += 1
    }

    func stop() {
        stops += 1
    }
}

/// A session store that keeps nothing. The record under test is the one on the
/// model; what the store does with it is `SessionStoreTests`' business.
struct DiscardingRecorder: SessionRecording {
    func record(_: SessionRecord) async {}

    func remove(_: SessionRecord.ID) async {}

    func merge(_: [SessionRecord]) async -> Bool {
        false
    }

    func recordedSessions() async -> [SessionRecord] {
        []
    }
}

/// Polls `condition` (on the main actor, allowed to suspend) until it holds:
/// what is waited on is a cue loop sleeping on a clock, not an operation with
/// a handle. The timeout is always real time, even over a `ManualClock` — it
/// bounds how long the loop may take to notice the clock moved, never how far
/// the plan travels. Callers waiting on a deliberate delay pass it plus slack.
@MainActor
func waitFor(
    _ description: String,
    within timeout: Duration = .seconds(1),
    until condition: @MainActor () async -> Bool
) async throws {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() {
            return
        }
        try await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("timed out waiting for \(description)")
}

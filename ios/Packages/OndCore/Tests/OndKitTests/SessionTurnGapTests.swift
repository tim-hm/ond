import Foundation
@testable import OndKit
import Testing

/// The beat of stillness at the seam between two phases. Two halves pinned
/// separately: the gap has to be *there* — sized by the phase's own tempo,
/// arriving before the boundary and resting — and it has to cost nothing:
/// the plan stays the plan the catalogue describes, boundary for boundary,
/// because the pause is borrowed from the breath, not inserted between.
@Suite("The turn between two phases")
struct SessionTurnGapTests {
    /// The calibration table, in the units the catalogue is authored in. The
    /// left column is every phase length the seeded techniques reach, from the
    /// sigh's dialled-down sip to a long exhale; the right is what each turn is
    /// worth. A tuning pass moves these numbers and `SessionTurnGap`'s together.
    @Test("A fast phase turns on a shorter pause than a slow one")
    func sizesTheGapByTempo() {
        let calibration = [
            // The sigh's sip at the bottom of its dial, and bellows breathing
            // at the bottom of its own — the fastest the catalogue goes.
            (phase: 500, gap: 25),
            (phase: 700, gap: 25),
            // Bellows and cyclic sighing's sip, at their curated defaults.
            (phase: 1000, gap: 25),
            // A Wim Hof power breath, mid-ramp.
            (phase: 1500, gap: 38),
            (phase: 2000, gap: 50),
            // Everything calm tops out here.
            (phase: 3000, gap: 75),
            (phase: 4000, gap: 75),
            (phase: 8000, gap: 75),
        ]

        for (phase, gap) in calibration {
            #expect(
                SessionTurnGap.length(ofPhase: .milliseconds(phase)) == .milliseconds(gap),
                "a \(phase) ms phase"
            )
        }
    }

    /// The floor cannot eat a phase shorter than itself. Nothing curated is
    /// this quick, but the test fixtures elsewhere in this suite breathe in
    /// tens of milliseconds, and a 30 ms phase that was 25 ms of stillness
    /// would be a timeline nobody could assert anything about.
    @Test("A phase never gives up more than a tenth of itself")
    func capsTheGapAgainstShortPhases() {
        #expect(SessionTurnGap.length(ofPhase: .milliseconds(30)) == .milliseconds(3))
        #expect(SessionTurnGap.length(ofPhase: .zero) == .zero)
    }

    @Test("A stacked breath gets a perceptible pause without consuming a short phase")
    func pausesBeforeAStackedBreath() {
        #expect(
            SessionTurnGap.length(
                ofPhase: .milliseconds(1500),
                beforeStackedBreath: true
            ) == .milliseconds(200)
        )
        #expect(
            SessionTurnGap.length(
                ofPhase: .milliseconds(1000),
                beforeStackedBreath: true
            ) == .milliseconds(200)
        )
        #expect(
            SessionTurnGap.length(
                ofPhase: .milliseconds(500),
                beforeStackedBreath: true
            ) == .milliseconds(100)
        )
    }

    @Test("The timeline puts the stacked pause on the departing breath")
    func laysOutAStackedPause() throws {
        let timeline = SessionTimeline(
            stages: [Stage(
                phases: [
                    Phase(kind: .inhale, duration: .milliseconds(1500)),
                    Phase(kind: .inhale, duration: .milliseconds(1000)),
                    Phase(kind: .exhale, duration: .milliseconds(5000)),
                ],
                cycles: 1
            )],
            rounds: 1
        )
        let opening = try #require(timeline.beats.first)
        let topUp = timeline.beats[1]

        #expect(opening.turnGap == .milliseconds(200))
        #expect(opening.breathing == .milliseconds(1300))
        #expect(topUp.turnGap == .milliseconds(25))
        #expect(timeline.totalDuration == .milliseconds(7500))
    }

    @Test("Both shipped sighs use the full stacked pause")
    func pausesBothShippedSighs() throws {
        for slug: TechniqueSlug in ["physiological-sigh", "cyclic-sighing"] {
            let technique = SeededCatalogue.technique(slug)
            let timeline = SessionTimeline(technique: technique)
            let stacked = try #require(timeline.beats.first { $0.stacksOnPrevious })
            try #require(stacked.id > 0)
            let preceding = timeline.beats[stacked.id - 1]

            #expect(preceding.turnGap == .milliseconds(200), "\(slug)")
        }
    }

    /// What the change is actually for: the orb tops out, holds where it
    /// arrived, and only then does the next phase begin. The countdown is
    /// deliberately untouched — it runs on the beat's whole span, so the last
    /// second still reads 1 and the stillness happens inside it.
    @Test("The breath arrives before the boundary and rests there")
    func restsAtTheArrivedFullness() throws {
        // Two-second phases, so the gap is 50 and the halfway point of the
        // breath lands on a whole millisecond.
        let timeline = SessionTimeline(
            stages: [Stage(
                phases: [Phase(kind: .inhale, duration: .milliseconds(2000))],
                cycles: 1
            )],
            rounds: 1
        )
        let inhale = try #require(timeline.beats.first)

        #expect(inhale.turnGap == .milliseconds(50))
        #expect(inhale.breathing == .milliseconds(1950))
        #expect(inhale.fraction(at: .milliseconds(975)) == 0.5)
        #expect(inhale.fraction(at: .milliseconds(1950)) == 1)

        let arrived = inhale.lungFullness(at: .milliseconds(1950))
        #expect(abs(arrived - 1) < 0.000001, "the breath finished full")
        #expect(inhale.lungFullness(at: .milliseconds(1999)) == arrived, "and held there")
        #expect(inhale.secondsRemaining(at: .milliseconds(1950)) == 1, "with the count still on")
    }

    /// A retention's length is a figure to aim for, never one the clock keeps,
    /// so there is no span to borrow from and no seam to soften — the tap ends
    /// it. Borrowing here would quietly shorten the number the screen suggests.
    @Test("A hold the person ends keeps its whole span")
    func leavesOpenEndedHoldsWhole() throws {
        let timeline = SessionTimeline(
            stages: [Stage(
                phases: [Phase(kind: .holdOut, duration: .milliseconds(60000))],
                cycles: 1,
                openEnded: true
            )],
            rounds: 1
        )
        let hold = try #require(timeline.beats.first)

        #expect(hold.turnGap == .zero)
        #expect(hold.breathing == hold.duration)
        #expect(hold.target == .milliseconds(60000))
    }

    /// The whole argument for borrowing the pause rather than inserting it: no
    /// seeded exercise gains a millisecond, so every length the app quotes —
    /// the dials, the cards, the marketing figures — still describes the
    /// session it plays.
    @Test("No seeded exercise grows by the gap")
    func keepsEverySeededDose() {
        for technique in SeededCatalogue.techniques {
            let timeline = SessionTimeline(technique: technique)

            for beat in timeline.beats {
                #expect(beat.breathing + beat.turnGap == beat.duration, "\(technique.slug)")

                // An open-ended hold is the one beat laid out at something other
                // than its authored length: it grows a helping each round.
                guard !beat.isOpenEnded else { continue }
                let authored = technique.stages[beat.stage].phases[beat.phase].duration
                #expect(beat.duration == authored, "\(technique.slug) phase \(beat.phase)")
            }

            guard !technique.hasOpenEndedStage else { continue }
            #expect(timeline.totalDuration == technique.plannedDuration, "\(technique.slug)")
        }
    }

    /// Named rather than left to the sweep above, because this is the one whose
    /// copy quotes its own length: thirty ten-second cycles are the dose the
    /// trial ran, and a gap added between phases rather than taken out of them
    /// would have made it 5m04s.
    @Test("Cyclic sighing still runs the five minutes it claims")
    func keepsTheTrialDose() {
        let timeline = SessionTimeline(technique: SeededCatalogue.technique("cyclic-sighing"))

        #expect(timeline.totalDuration == .seconds(300))
    }
}

/// The gap seen from the cue loop rather than the plan: a clocked session
/// still turns over on the authored boundary, not a gap's width either side.
/// This guards a cue that moves with the gap — an instruction arriving while
/// the countdown reads 1 is overlap, one arriving a gap late is the whole
/// session sliding, and drift of either sign produces one of the two.
@MainActor
@Suite("A session's boundaries with a turn gap in them")
struct SessionTurnGapClockTests {
    /// Two two-second phases, twice: a 50 ms gap on each, and a total the
    /// arithmetic below can be checked against by hand.
    private static let evenBreathing = Technique(
        id: "id",
        slug: "coherent-breathing",
        name: "Coherent Breathing",
        summary: "",
        goal: .calm,
        stages: [
            Stage(
                phases: [
                    Phase(kind: .inhale, duration: .milliseconds(2000)),
                    Phase(kind: .exhale, duration: .milliseconds(2000)),
                ],
                cycles: 2
            ),
        ],
        recommendedRounds: 1
    )

    @Test("The next phase is cued on the boundary, not at the end of the breath")
    func cuesOnTheAuthoredBoundary() async throws {
        let cues = RecordingCues()
        let clock = ManualClock()
        let model = SessionModel(
            technique: Self.evenBreathing,
            cues: cues,
            recorder: DiscardingRecorder(),
            clock: clock
        )

        model.start()
        try await waitFor("the first breath") { model.currentBeat?.id == 0 }

        clock.advance(by: .milliseconds(1950))
        let breath = try #require(model.currentBeat)
        #expect(breath.id == 0, "the breath is done but the phase is not")
        #expect(breath.fraction(at: model.elapsed) == 1, "and it is resting where it arrived")

        clock.advance(by: .milliseconds(49))
        #expect(model.currentBeat?.id == 0, "still nothing new asked")
        #expect(cues.played.count == 1)

        clock.advance(by: .milliseconds(1))
        try await waitFor("the breath out") { model.currentBeat?.id == 1 }
        #expect(cues.played.count == 2, "cued once, on the boundary the catalogue authored")
    }

    /// Cycle boundaries, the recorded length and completion all come off the
    /// plan's own arithmetic, so a gap that had leaked into the axis would show
    /// up here as an eight-second session that ran eight and a bit.
    @Test("The session's own accounting is untouched")
    func countsTheSessionOut() async throws {
        let clock = ManualClock()
        let model = SessionModel(
            technique: Self.evenBreathing,
            cues: RecordingCues(),
            recorder: DiscardingRecorder(),
            clock: clock
        )

        model.start()
        for id in 1 ... 3 {
            clock.advance(by: .milliseconds(2000))
            try await waitFor("phase \(id)") { model.currentBeat?.id == id }
        }
        #expect(model.timeline.cyclesCompleted(at: model.elapsed) == 1)

        clock.advance(by: .milliseconds(2000))
        try await waitFor("the session to finish") { model.status == .finished }

        let record = try #require(model.record)
        #expect(record.completed)
        #expect(record.cyclesCompleted == 2)
        #expect(record.duration == .milliseconds(8000), "four two-second phases, and no more")
    }
}

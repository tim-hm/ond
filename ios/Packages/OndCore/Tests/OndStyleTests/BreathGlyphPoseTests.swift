import Foundation
import OndKit
@testable import OndStyle
import OndUI
import Testing

/// The arithmetic that puts a session's breath into the shared glyph — pinned
/// because four surfaces draw from it, and a drift in the pose is a breath
/// that visibly disagrees between the hand, the wrist and the lock screen.
@Suite("Breath glyph posing")
struct BreathGlyphPoseTests {
    /// Box 4-4-6-2, the spec's own decoding target.
    private var box: SessionTimeline {
        SessionTimeline(
            stages: [Stage(
                phases: [
                    Phase(kind: .inhale, duration: .seconds(4)),
                    Phase(kind: .holdIn, duration: .seconds(4)),
                    Phase(kind: .exhale, duration: .seconds(6)),
                    Phase(kind: .holdOut, duration: .seconds(2)),
                ],
                cycles: 2
            )],
            rounds: 1
        )
    }

    private func isClose(
        _ value: Double,
        _ expected: Double,
        within tolerance: Double = 0.02
    ) -> Bool {
        abs(value - expected) < tolerance
    }

    @Test("the pose walks the spec's motion table through one box cycle")
    func boxCycleMatchesTheSpecTable() {
        // Empty lungs at the very start: half scale, rings at their floor.
        let start = BreathGlyph.Pose(timeline: box, elapsed: .zero)
        #expect(isClose(start.coreScale, 0.5))
        #expect(isClose(start.coreOpacity, 0.5))
        #expect(isClose(start.ringScale, 0.62))

        // Top of the inhale — full: everything at its ceiling. Sampled just
        // inside the breathing span because the turn gap shaves the very end.
        let full = BreathGlyph.Pose(timeline: box, elapsed: .seconds(3.9))
        #expect(isClose(full.coreScale, 1.0))
        #expect(isClose(full.ringScale, 1.06))

        // Mid-hold: held at the top, nothing scaling.
        let held = BreathGlyph.Pose(timeline: box, elapsed: .seconds(6))
        #expect(isClose(held.coreScale, 1.0))
        #expect(isClose(held.ringScale, 1.06))

        // The exhale reverses over its own six seconds.
        let falling = BreathGlyph.Pose(timeline: box, elapsed: .seconds(11))
        #expect(falling.coreScale < held.coreScale)
        #expect(falling.coreScale > 0.5)

        // Rest holds at the bottom.
        let rest = BreathGlyph.Pose(timeline: box, elapsed: .seconds(15))
        #expect(isClose(rest.coreScale, 0.5))
        #expect(isClose(rest.ringScale, 0.62))
    }

    @Test("the hold crossfades across the boundary, not at it")
    func holdStraddlesTheBoundary() {
        // The box hold starts at 4s. Half the 0.8s window either side.
        let before = BreathGlyph.Pose(timeline: box, elapsed: .seconds(3.5))
        let boundary = BreathGlyph.Pose(timeline: box, elapsed: .seconds(4))
        let after = BreathGlyph.Pose(timeline: box, elapsed: .seconds(4.5))
        let mid = BreathGlyph.Pose(timeline: box, elapsed: .seconds(6))

        #expect(before.holdPresence == 0)
        #expect(isClose(boundary.holdPresence, 0.5))
        #expect(after.holdPresence == 1)
        #expect(mid.holdPresence == 1)

        // And out again over the hold's end at 8s.
        let leaving = BreathGlyph.Pose(timeline: box, elapsed: .seconds(8))
        let gone = BreathGlyph.Pose(timeline: box, elapsed: .seconds(8.5))
        #expect(isClose(leaving.holdPresence, 0.5))
        #expect(gone.holdPresence == 0)
    }

    @Test("both hold kinds carry the count")
    func holdOutCarriesTheCountToo() {
        // The box holdOut runs 14s...16s of a 16s cycle.
        let holdingOut = BreathGlyph.Pose(timeline: box, elapsed: .seconds(15))
        #expect(holdingOut.holdPresence == 1)
    }

    @Test("a technique with no holds never shows the count")
    func noHoldsMeansNoCount() {
        let coherent = SessionTimeline(
            stages: [Stage(
                phases: [
                    Phase(kind: .inhale, duration: .seconds(5.5)),
                    Phase(kind: .exhale, duration: .seconds(5.5)),
                ],
                cycles: 3
            )],
            rounds: 1
        )

        for tenths in stride(from: 0.0, through: 33, by: 0.5) {
            let pose = BreathGlyph.Pose(timeline: coherent, elapsed: .seconds(tenths))
            #expect(pose.holdPresence == 0, "the count appeared at \(tenths)s")
        }
    }

    @Test("a short hold clamps its crossfade instead of overshooting")
    func shortHoldClampsTheWindow() {
        let snappy = SessionTimeline(
            stages: [Stage(
                phases: [
                    Phase(kind: .inhale, duration: .seconds(4)),
                    Phase(kind: .holdIn, duration: .seconds(0.5)),
                    Phase(kind: .exhale, duration: .seconds(4)),
                ],
                cycles: 1
            )],
            rounds: 1
        )

        // The window clamps to the hold's own half second, so the ramps meet
        // at full presence mid-hold rather than overlapping into nonsense.
        let mid = BreathGlyph.Pose(timeline: snappy, elapsed: .seconds(4.25))
        #expect(mid.holdPresence == 1)

        // Well before the ramp could reach at the clamped width, nothing.
        let early = BreathGlyph.Pose(timeline: snappy, elapsed: .seconds(3.5))
        #expect(early.holdPresence == 0)
    }

    /// The sigh's second sip starts nine tenths full — the reason the pose
    /// rides the fullness envelope instead of the phase kind.
    @Test("a stacked inhale starts where the plan put it, not at empty")
    func stackedInhaleKeepsItsLayout() throws {
        let sigh = SessionTimeline(
            stages: [Stage(
                phases: [
                    Phase(kind: .inhale, duration: .milliseconds(1500)),
                    Phase(kind: .inhale, duration: .milliseconds(700)),
                    Phase(kind: .exhale, duration: .seconds(5)),
                ],
                cycles: 1
            )],
            rounds: 1
        )
        let sip = try #require(sigh.beats.first { $0.stacksOnPrevious })

        let opening = BreathGlyph.Pose(timeline: sigh, elapsed: sip.start)
        #expect(opening.coreScale > 0.9)
    }

    /// A retention freezes the plan clock exactly on the hold's start, so the
    /// fade must be complete there — a half-faded count for a whole retention
    /// is the bug this pins against.
    @Test("an open-ended hold is fully present at its own start")
    func openEndedHoldArrivesAtItsStart() {
        let retention = SessionTimeline(
            stages: [
                Stage(phases: [
                    Phase(kind: .inhale, duration: .seconds(2)),
                    Phase(kind: .exhale, duration: .seconds(2)),
                ], cycles: 1),
                Stage(
                    phases: [Phase(kind: .holdOut, duration: .seconds(60))],
                    cycles: 1,
                    openEnded: true
                ),
            ],
            rounds: 1
        )
        let hold = retention.beats.last

        guard let hold, hold.isOpenEnded else {
            Issue.record("the retention lost its open-ended hold")
            return
        }

        let arrival = BreathGlyph.Pose(timeline: retention, elapsed: hold.start)
        #expect(arrival.holdPresence == 1)
    }

    @Test("a plan that opens on a hold shows the count from its first frame")
    func openingHoldArrivesComplete() {
        let holdFirst = SessionTimeline(
            stages: [Stage(
                phases: [
                    Phase(kind: .holdIn, duration: .seconds(4)),
                    Phase(kind: .exhale, duration: .seconds(4)),
                ],
                cycles: 1
            )],
            rounds: 1
        )

        // No boundary to straddle: half a crossfade at the very first frame
        // would show the ramp's midpoint as a state.
        let opening = BreathGlyph.Pose(timeline: holdFirst, elapsed: .zero)
        #expect(opening.holdPresence == 1)
    }

    @Test("before the first beat the pose rests")
    func restsBeforeTheFirstBeat() {
        let pose = BreathGlyph.Pose(timeline: box, elapsed: .seconds(-1))
        #expect(pose == .rest)
    }

    @Test("a pushed pose draws the phase's target state")
    func pushedPosesLandOnTargets() {
        let inhale = BreathGlyph.Pose.pushed(breath: .inhale(through: .nose), isPaused: false)
        #expect(isClose(inhale.coreScale, 1.0))
        #expect(inhale.holdPresence == 0)

        let hold = BreathGlyph.Pose.pushed(breath: .holdIn, isPaused: false)
        #expect(isClose(hold.coreScale, 1.0))
        #expect(hold.holdPresence == 1)

        let exhale = BreathGlyph.Pose.pushed(breath: .exhale(through: .nose), isPaused: false)
        #expect(isClose(exhale.coreScale, 0.5))
        #expect(exhale.holdPresence == 0)

        // Paused during a hold: the words say "Paused", and a count running
        // down a hold nobody is in would contradict them.
        let paused = BreathGlyph.Pose.pushed(breath: .holdIn, isPaused: true)
        #expect(paused.holdPresence == 0)
    }

    @Test("the sweeping pose parks the core and still marks a hold")
    func sweepingPosesHoldStill() {
        let phases: [Breath] = [.inhale(through: .nose), .holdIn, .exhale(through: .nose)]
        let poses = phases.map { BreathGlyph.Pose.sweeping(breath: $0, isPaused: false) }

        #expect(poses.allSatisfy { $0.coreScale == BreathGlyph.Pose.full.coreScale })
        #expect(poses.allSatisfy { $0.coreOpacity == BreathGlyph.Pose.full.coreOpacity })
        #expect(poses.map(\.holdPresence) == [0, 1, 0])
    }

    @Test("the resting pose breathes inside its band and never holds")
    func restingStaysInItsBand() {
        for time in stride(from: 0.0, through: AmbientBreath.restingCycle, by: 0.25) {
            let pose = BreathGlyph.Pose.resting(at: time)
            let level = (pose.coreScale - 0.5) / 0.5
            #expect(level >= 0.24 && level <= 0.86, "resting level \(level) left the band")
            #expect(pose.holdPresence == 0)
        }
    }

    @Test("the resting pose is fullest half a breath in, at Coherent pace")
    func restingIsCoherent() {
        let half = AmbientBreath.restingCycle / 2
        #expect(half == 5.5)
        #expect(BreathGlyph.Pose.resting(at: half).coreScale > BreathGlyph.Pose.resting(at: 0)
            .coreScale)
        #expect(BreathGlyph.Pose.resting(at: 0) == BreathGlyph.Pose
            .resting(at: AmbientBreath.restingCycle))
    }
}

/// The resting orb and the exercise Home starts by default have to be one
/// breath — the screen says so by drawing them together.
@Suite("The resting breath and the catalogue")
struct RestingBreathTests {
    @Test("The resting cycle is the seeded Coherent breath")
    func theRestingCycleIsCoherent() throws {
        let coherent = try #require(
            CatalogueExport.bundled.techniques.first { $0.slug == HomeOffer.restingSlug }
        )
        let cycle = try #require(coherent.stages.first?.cycleDuration)

        #expect(
            Duration.seconds(AmbientBreath.restingCycle) == cycle,
            "the orb breathes at the pace the button starts"
        )
    }
}

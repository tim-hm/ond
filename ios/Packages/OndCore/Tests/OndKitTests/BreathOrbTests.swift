import Foundation
@testable import OndKit
import Testing

/// The orb's two resting shapes and the tumble between them.
///
/// What is pinned is the contract the animation is built on: every phase
/// starts and settles on one flat circle — whole revolutions are the identity
/// — the spin lives on the phase's own clock with its rise, cruise and
/// earlier stop, and a hold moves nothing. The axes are "random", but as a
/// pure function of the breath's seed, which is why a test can name them.
@Suite("Breath orb")
struct BreathOrbTests {
    private func pose(
        level: Double = 0.5,
        progress: Double = 0.5,
        kind: PhaseKind? = .inhale,
        breath: Int = 7,
        side: Passage.Side? = nil
    ) -> BreathOrb.Pose {
        BreathOrb.pose(
            atLevel: level,
            through: progress,
            during: kind,
            breath: breath,
            toward: side
        )
    }

    /// Angle modulo a full turn, folded to the nearest distance from flat.
    private func offFlat(_ angle: Double) -> Double {
        let wrapped = abs(angle.truncatingRemainder(dividingBy: 360))
        return min(wrapped, 360 - wrapped)
    }

    @Test("Fully exhaled the drawing is the dot alone")
    func exhaledIsADot() {
        let exhaled = pose(level: 0, progress: 1, kind: .exhale)

        #expect(exhaled.scale == BreathOrb.dotScale)
        #expect(exhaled.ringScale == 0)
        #expect(exhaled.bodyOpacity == 1)
        #expect(exhaled.ringOpacity == 0)
        #expect(exhaled.rings.allSatisfy { $0.angle == 0 })
        #expect(exhaled.lean == 0)
        // Before the first beat there is no kind yet, and the rest is the
        // same dot.
        #expect(pose(level: 0, progress: 0, kind: nil).bodyOpacity == 1)
    }

    @Test("Near empty the rings sit inside the ball, on their way to its centre")
    func contractionCollapsesInward() {
        #expect(pose(level: 0.1).ringScale < pose(level: 0.1).scale)
    }

    @Test("An exhale is the soft sphere alone: no spin, no lean, no cage")
    func exhaleOnlyContracts() {
        for progress in [0.2, 0.5, 0.8] {
            let pose = pose(level: 1 - progress, progress: progress, kind: .exhale, side: .right)

            #expect(pose.rings.allSatisfy { $0.angle == 0 })
            #expect(pose.lean == 0)
            #expect(pose.ringOpacity == 0)
            #expect(pose.bodyOpacity == 1)
        }
    }

    @Test("An inhale is bare rings: no body under the cage at any level")
    func inhaleIsBareRings() {
        for level in [0.0, 0.15, 0.5, 1.0] {
            #expect(pose(level: level).bodyOpacity == 0)
        }
        #expect(pose(level: 0.5).ringOpacity == 1)
    }

    @Test("The top hold keeps the circle, the bottom hold the dot")
    func holdsKeepTheirShape() {
        #expect(pose(level: 1, kind: .holdIn).bodyOpacity == 0)
        #expect(pose(level: 1, kind: .holdIn).ringOpacity == 1)
        #expect(pose(level: 0, kind: .holdOut).bodyOpacity == 1)
    }

    @Test("A settled inhale is one circle again, by whole revolutions")
    func settlesOnWholeRevolutions() {
        for progress in [BreathOrb.settled, 0.98, 1] {
            let pose = pose(level: 1, progress: progress, side: .left)

            #expect(pose.scale == 1)
            #expect(pose.ringScale == 1)
            #expect(pose.rings.allSatisfy { offFlat($0.angle) < 0.000001 })
            #expect(abs(pose.lean) < 0.000001)
        }
    }

    /// The hold-boundary pin: the crossfade that runs when a hold begins
    /// animates whatever the angle *value* does, so a settled breath and the
    /// hold after it must hand over identical angles — not merely identical
    /// orientations — or the rings spin visibly backwards through their
    /// revolutions at the boundary.
    @Test("A settled inhale and the hold after it share one animatable angle")
    func settledMatchesTheHold() {
        let settled = pose(level: 1, progress: BreathOrb.settled, breath: 7)
        let hold = pose(level: 1, progress: 0.1, kind: .holdIn, breath: 8)

        #expect(settled.rings.map(\.angle) == hold.rings.map(\.angle))
    }

    @Test("Mid-phase the rings are scattered, each on its own three-dimensional axis")
    func midPhaseTumbles() {
        let pose = pose()

        #expect(pose.rings.count == BreathOrb.ringCount)
        #expect(pose.rings.allSatisfy { offFlat($0.angle) > 1 })

        for ring in pose.rings {
            let length = (ring.axisX * ring.axisX + ring.axisY * ring.axisY
                + ring.axisZ * ring.axisZ).squareRoot()
            #expect(abs(length - 1) < 0.000001)
            // Never the pure z axis: a circle spun about z is a circle, and
            // that ring would sit still through the whole breath.
            #expect(abs(ring.axisZ) < 0.9)
        }
        #expect(
            pose.rings.contains { $0.axisZ != 0 },
            "the tumble is three-dimensional, not an in-plane fan"
        )
        #expect(
            Set(pose.rings.map(\.axisX)).count == pose.rings.count,
            "every ring turns its own way"
        )
    }

    @Test("Each breath tumbles its own way, and the same breath always the same way")
    func axesAreSeededPerBreath() {
        #expect(pose(breath: 1) == pose(breath: 1))
        #expect(pose(breath: 1).rings[0].axisX != pose(breath: 2).rings[0].axisX)
    }

    @Test(
        "A hold moves nothing, whatever its progress says",
        arguments: [PhaseKind.holdIn, .holdOut]
    )
    func holdsAreStill(_ kind: PhaseKind) {
        for progress in [0.0, 0.3, 0.7] {
            let pose = pose(level: 1, progress: progress, kind: kind, side: .left)

            #expect(pose.rings.allSatisfy { $0.angle == 0 })
            #expect(pose.lean == 0)
        }
    }

    @Test("The spin rises fast, cruises, and has stopped before the phase ends")
    func spinRisesCruisesAndStopsEarly() {
        // Monotonic throughout — a tumble never rewinds.
        var previous = -0.1
        for step in 0 ... 20 {
            let turn = BreathOrb.turn(through: Double(step) / 20)
            #expect(turn >= previous)
            previous = turn
        }

        #expect(BreathOrb.turn(through: 0) == 0)
        #expect(BreathOrb.turn(through: 1) == 1)
        // Accelerating out of the gate: the second half of the rise covers
        // more ground than the first.
        let half = BreathOrb.riseWindow / 2
        #expect(
            BreathOrb.turn(through: BreathOrb.riseWindow) - BreathOrb.turn(through: half)
                > BreathOrb.turn(through: half)
        )
        // Settled from `settled` onwards — the last sliver of the phase is
        // stillness, not drift.
        #expect(BreathOrb.turn(through: BreathOrb.settled) == 1)
        #expect(BreathOrb.turn(through: 0.98) == 1)
        // Still cruising at two-thirds, braking smoothly just after: the
        // velocity has no corner at `fallStart`.
        #expect(BreathOrb.envelope(through: BreathOrb.fallStart) == 1)
        #expect(BreathOrb.envelope(through: BreathOrb.fallStart + 0.03) > 0.9)
        // And the brake itself dies away: nearly no speed left near the stop.
        #expect(BreathOrb.envelope(through: BreathOrb.settled - 0.01) < 0.05)
    }

    @Test("The lean rides the spin's envelope and mirrors with the nostril")
    func leanRidesTheEnvelope() {
        let left = pose(side: .left)
        let right = pose(side: .right)

        #expect(left.lean > 0)
        #expect(left.lean == -right.lean)
        // No side, no lean — a nose breath has nothing to point at.
        #expect(pose(side: nil).lean == 0)
        // Gone at both ends of the phase, so a boundary never snaps it.
        #expect(pose(progress: 0, side: .left).lean == 0)
        #expect(pose(progress: BreathOrb.settled, side: .left).lean == 0)
    }
}

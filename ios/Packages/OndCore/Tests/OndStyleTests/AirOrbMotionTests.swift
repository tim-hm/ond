import OndKit
@testable import OndStyle
import Testing

@Suite("Air orb motion")
struct AirOrbMotionTests {
    private let timeline = SessionTimeline(stages: [Stage(phases: [
        Phase(kind: .inhale, duration: .seconds(4)),
        Phase(kind: .holdIn, duration: .seconds(4)),
        Phase(kind: .exhale, duration: .seconds(6)),
        Phase(kind: .holdOut, duration: .seconds(2)),
    ], cycles: 2)], rounds: 1)

    @Test("Both holds circulate softly at a constant size and resume without a jump")
    func holdsCirculate() {
        let motion = AirOrbMotion(timeline: timeline)
        for beat in timeline.beats where beat.kind.isHold {
            let entry = motion.frame(at: beat.start)
            let middle = motion.frame(at: beat.start + beat.duration / 2)
            let last = motion.frame(at: beat.end - .milliseconds(1))
            #expect(entry.scale == middle.scale)
            #expect(entry.scale == last.scale)
            #expect(middle.swirl > entry.swirl)
            #expect(last.swirl > middle.swirl)
            #expect(abs((last.swirl - entry.swirl) / (beat.duration / .seconds(1)) - 0.012) <
                0.0001)
            if beat.end < timeline.totalDuration {
                let next = motion.frame(at: beat.end)
                #expect(abs(last.swirl - next.swirl) < 0.0001)
                #expect(abs(entry.scale - next.scale) < 0.0001)
            }
        }
    }

    @Test("Growth and shrinkage follow the breath while turn gaps keep their size")
    func breathsMove() {
        let motion = AirOrbMotion(timeline: timeline)
        #expect(motion.frame(at: .seconds(3)).scale > motion.frame(at: .seconds(1)).scale)
        #expect(motion.frame(at: .seconds(13)).scale < motion.frame(at: .seconds(9)).scale)
        #expect(motion.frame(at: .seconds(3)).swirl > motion.frame(at: .seconds(1)).swirl)
        for beat in timeline.beats where !beat.kind.isHold && beat.turnGap > .zero {
            #expect(motion.frame(at: beat.start + beat.breathing).scale
                == motion.frame(at: beat.end - .milliseconds(1)).scale)
        }
    }

    @Test("Air accelerates then slows within a breath")
    func breathSpeedEnvelope() {
        let motion = AirOrbMotion(timeline: timeline)
        let early = motion.frame(at: .milliseconds(200)).swirl - motion.frame(at: .zero).swirl
        let middle = motion.frame(at: .milliseconds(2100)).swirl
            - motion.frame(at: .milliseconds(1900)).swirl
        let late = motion.frame(at: .seconds(4)).swirl
            - motion.frame(at: .milliseconds(3800)).swirl
        #expect(middle > early * 4)
        #expect(middle > late * 4)
        #expect(motion.frame(at: .zero).scale < motion.frame(at: .seconds(4)).scale / 2)
    }

    @Test("Reduced motion keeps the same globe across every phase")
    func stationaryGlobe() {
        let motion = AirOrbMotion(timeline: timeline)
        let initial = motion.frame(at: .zero, stationary: true)
        for beat in timeline.beats {
            #expect(motion.frame(at: beat.start + beat.duration / 2, stationary: true) == initial)
        }
    }

    @Test("A second inhale stays continuous and an open hold uses real elapsed time")
    func specialBreaths() throws {
        let special = SessionTimeline(stages: [
            Stage(phases: [
                Phase(kind: .inhale, duration: .milliseconds(1500)),
                Phase(kind: .inhale, duration: .milliseconds(700)),
                Phase(kind: .exhale, duration: .seconds(5)),
            ], cycles: 1),
            Stage(
                phases: [Phase(kind: .holdOut, duration: .seconds(60))],
                cycles: 1,
                openEnded: true
            ),
        ], rounds: 1)
        let motion = AirOrbMotion(timeline: special)
        let sip = try #require(special.beats.first { $0.stacksOnPrevious })
        let beforeSip = motion.frame(at: sip.start - .milliseconds(1))
        let atSip = motion.frame(at: sip.start)
        #expect(atSip.scale > 0.9)
        #expect(abs(beforeSip.scale - atSip.scale) < 0.0001)
        #expect(abs(beforeSip.swirl - atSip.swirl) < 0.0001)
        let hold = try #require(special.beats.first { $0.isOpenEnded })
        let entry = motion.frame(at: hold.start, realElapsed: hold.start)
        let held = motion.frame(at: hold.start, realElapsed: hold.start + .seconds(30))
        #expect(entry.scale == held.scale)
        #expect(abs(held.swirl - entry.swirl - 0.36) < 0.0001)
    }
}

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

    @Test("Both holds freeze every part of the orb and resume without a jump")
    func holdsFreeze() {
        let motion = AirOrbMotion(timeline: timeline)
        for beat in timeline.beats where beat.kind.isHold {
            let entry = motion.frame(at: beat.start)
            #expect(entry == motion.frame(at: beat.start + beat.duration / 2))
            #expect(entry == motion.frame(at: beat.end - .milliseconds(1)))
            if beat.end < timeline.totalDuration {
                let next = motion.frame(at: beat.end)
                #expect(abs(entry.swirl - next.swirl) < 0.0001)
                #expect(abs(entry.scale - next.scale) < 0.0001)
            }
        }
    }

    @Test("Growth and shrinkage follow the breath while turn gaps remain still")
    func breathsMove() {
        let motion = AirOrbMotion(timeline: timeline)
        #expect(motion.frame(at: .seconds(3)).scale > motion.frame(at: .seconds(1)).scale)
        #expect(motion.frame(at: .seconds(13)).scale < motion.frame(at: .seconds(9)).scale)
        #expect(motion.frame(at: .seconds(3)).swirl > motion.frame(at: .seconds(1)).swirl)
        for beat in timeline.beats where !beat.kind.isHold && beat.turnGap > .zero {
            #expect(motion.frame(at: beat.start + beat.breathing)
                == motion.frame(at: beat.end - .milliseconds(1)))
        }
    }

    @Test("Reduced motion keeps the same globe across every phase")
    func stationaryGlobe() {
        let motion = AirOrbMotion(timeline: timeline)
        let initial = motion.frame(at: .zero, stationary: true)
        for beat in timeline.beats {
            #expect(motion.frame(at: beat.start + beat.duration / 2, stationary: true) == initial)
        }
    }

    @Test("A second inhale continues from full lungs and an open hold stays still")
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
        #expect(motion.frame(at: hold.start) == motion.frame(at: hold.start + .seconds(30)))
    }
}

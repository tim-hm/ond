import OndKit
import Testing

/// The authored phase shapes both device renderers promise to preserve.
@Suite("Session haptic shapes")
struct SessionHapticShapeTests {
    private func beats(_ phases: [Phase]) -> [SessionTimeline.Beat] {
        SessionTimeline(stages: [Stage(phases: phases, cycles: 1)], rounds: 1).beats
    }

    @Test("A full breath keeps the phone's tuned endpoints")
    func fullBreathEndpoints() throws {
        let beats = beats([
            Phase(kind: .inhale, duration: .seconds(4)),
            Phase(kind: .exhale, duration: .seconds(4)),
        ])

        let inhale = try #require(beats.first)
        let exhale = try #require(beats.last)
        #expect(
            SessionHapticShape(beat: inhale)
                == .continuous(startIntensity: 0.12, endIntensity: 0.85, sharpness: 0.3)
        )
        #expect(
            SessionHapticShape(beat: exhale)
                == .continuous(startIntensity: 0.8, endIntensity: 0.08, sharpness: 0.1)
        )
    }

    @Test("The two holds keep their distinct taps")
    func holdTaps() {
        let beats = beats([
            Phase(kind: .inhale, duration: .seconds(4)),
            Phase(kind: .holdIn, duration: .seconds(4)),
            Phase(kind: .exhale, duration: .seconds(4)),
            Phase(kind: .holdOut, duration: .seconds(4)),
        ])

        #expect(SessionHapticShape(beat: beats[1]) == .transient(intensity: 0.9, sharpness: 0.8))
        #expect(SessionHapticShape(beat: beats[3]) == .transient(intensity: 0.45, sharpness: 0.1))
    }

    @Test("A stacked inhale authors only its final top-up")
    func stackedInhale() throws {
        let beats = beats([
            Phase(kind: .inhale, duration: .milliseconds(1500)),
            Phase(kind: .inhale, duration: .milliseconds(700)),
            Phase(kind: .exhale, duration: .seconds(5)),
        ])
        let sip = try #require(beats.dropFirst().first)

        guard case let .continuous(startIntensity, endIntensity, sharpness)
            = SessionHapticShape(beat: sip)
        else {
            Issue.record("the sigh's sip did not produce a continuous shape")
            return
        }
        #expect(startIntensity > 0.75)
        #expect(startIntensity < endIntensity)
        #expect(endIntensity == 0.85)
        #expect(sharpness == 0.3)
    }
}

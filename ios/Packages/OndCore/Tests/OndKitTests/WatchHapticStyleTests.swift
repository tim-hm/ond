import OndKit
import Testing

/// The sparse watch translation of the phone-authored haptic envelope.
@Suite("Watch haptic style")
struct WatchHapticStyleTests {
    private func beat(
        for phases: [Phase],
        at index: Int = 0
    ) -> SessionTimeline.Beat {
        SessionTimeline(stages: [Stage(phases: phases, cycles: 1)], rounds: 1).beats[index]
    }

    private func gaps(of offsets: [Duration]) -> [Duration] {
        zip(offsets.dropFirst(), offsets).map { $0 - $1 }
    }

    private let fullInhale = Phase(kind: .inhale, duration: .milliseconds(4000))
    private let fullExhale = Phase(kind: .exhale, duration: .milliseconds(4000))

    @Test("The inhale gathers and the exhale falls away")
    func followsTheEnvelope() {
        let style = WatchHapticStyle(strength: .standard)
        let inhale = beat(for: [fullInhale])
        let exhale = beat(for: [fullExhale])
        let inhaleGaps = gaps(of: style.pulses(
            over: inhale.breathing,
            shape: SessionHapticShape(beat: inhale)
        ))
        let exhaleGaps = gaps(of: style.pulses(
            over: exhale.breathing,
            shape: SessionHapticShape(beat: exhale)
        ))

        #expect(zip(inhaleGaps.dropFirst(), inhaleGaps).allSatisfy { $0 < $1 })
        #expect(zip(exhaleGaps.dropFirst(), exhaleGaps).allSatisfy { $0 > $1 })
    }

    @Test("A standard four-second breath stays restrained")
    func balancedDensity() {
        let style = WatchHapticStyle(strength: .standard)
        let inhale = beat(for: [fullInhale])
        let exhale = beat(for: [fullExhale])
        let counts = [inhale, exhale].map {
            style.pulses(over: $0.breathing, shape: SessionHapticShape(beat: $0)).count
        }

        #expect(counts.allSatisfy { 5 ... 7 ~= $0 })
    }

    @Test("Strength changes density without changing the envelope")
    func strengthChangesDensity() {
        let exhale = beat(for: [fullExhale])
        let shape = SessionHapticShape(beat: exhale)
        let counts = HapticStrength.allCases.map {
            WatchHapticStyle(strength: $0).pulses(over: exhale.breathing, shape: shape).count
        }

        #expect(counts == counts.sorted())
        #expect(Set(counts).count == counts.count)
    }

    @Test("Clicks leave both phase boundaries quiet")
    func leavesBoundaryRoom() throws {
        let inhale = beat(for: [fullInhale])
        let offsets = WatchHapticStyle(strength: .strong).pulses(
            over: inhale.breathing,
            shape: SessionHapticShape(beat: inhale)
        )
        let first = try #require(offsets.first)
        let last = try #require(offsets.last)

        #expect(first >= .milliseconds(300))
        #expect(last < inhale.breathing - .milliseconds(300))
        #expect(zip(offsets.dropFirst(), offsets).allSatisfy { $0 > $1 })
    }

    @Test("A protocol seam shifts the whole opening window")
    func leavesRoomForASeam() throws {
        let inhale = beat(for: [fullInhale])
        let offsets = WatchHapticStyle(strength: .standard).pulses(
            over: inhale.breathing,
            shape: SessionHapticShape(beat: inhale),
            cueDelay: .milliseconds(350)
        )

        #expect(try #require(offsets.first) >= .milliseconds(650))
        #expect(offsets.allSatisfy { $0 < inhale.breathing - .milliseconds(300) })
    }

    @Test("A phase with no click window keeps only its boundary cue")
    func shortPhaseHasNoPulses() {
        let shape = SessionHapticShape(beat: beat(for: [fullInhale]))
        let offsets = WatchHapticStyle(strength: .strong).pulses(
            over: .milliseconds(600),
            shape: shape
        )

        #expect(offsets.isEmpty)
    }

    @Test("The sigh's sip stays denser than an empty-lung inhale")
    func sipStaysDense() throws {
        let phases = [
            Phase(kind: .inhale, duration: .milliseconds(1500)),
            Phase(kind: .inhale, duration: .milliseconds(1000)),
            Phase(kind: .exhale, duration: .seconds(5)),
        ]
        let opening = beat(for: phases)
        let sip = beat(for: phases, at: 1)
        let style = WatchHapticStyle(strength: .standard)
        let openingOffsets = style.pulses(
            over: .milliseconds(3925),
            shape: SessionHapticShape(beat: opening)
        )
        let sipOffsets = style.pulses(
            over: .milliseconds(3925),
            shape: SessionHapticShape(beat: sip)
        )

        let openingGap = try #require(gaps(of: openingOffsets).first)
        let sipGap = try #require(gaps(of: sipOffsets).first)
        #expect(sipGap < openingGap)
    }

    @Test("The two holds remain distinct at every strength")
    func distinguishesHolds() throws {
        for strength in HapticStrength.allCases {
            let style = WatchHapticStyle(strength: strength)
            let holdIn = try #require(style.holdTap(for: .holdIn))
            let holdOut = try #require(style.holdTap(for: .holdOut))

            #expect(holdIn > holdOut)
            #expect(style.holdTap(for: .complete) == nil)
        }
    }

    @Test("Transient shapes never produce breath clicks")
    func transientHasNoPulses() {
        let offsets = WatchHapticStyle(strength: .strong).pulses(
            over: .seconds(4),
            shape: .transient(intensity: 0.9, sharpness: 0.8)
        )

        #expect(offsets.isEmpty)
    }
}

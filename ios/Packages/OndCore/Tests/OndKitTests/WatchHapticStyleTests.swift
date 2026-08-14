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
        let style = WatchHapticStyle()
        let inhale = beat(for: [fullInhale])
        let exhale = beat(for: [fullExhale])
        let inhaleGaps = gaps(of: style.pulses(for: inhale))
        let exhaleGaps = gaps(of: style.pulses(for: exhale))

        #expect(zip(inhaleGaps.dropFirst(), inhaleGaps).allSatisfy { $0 < $1 })
        #expect(zip(exhaleGaps.dropFirst(), exhaleGaps).allSatisfy { $0 > $1 })
    }

    @Test("A standard four-second breath stays restrained")
    func balancedDensity() {
        let style = WatchHapticStyle()
        let inhale = beat(for: [fullInhale])
        let exhale = beat(for: [fullExhale])
        let counts = [inhale, exhale].map { style.pulses(for: $0).count }

        #expect(counts.allSatisfy { 5 ... 7 ~= $0 })
    }

    @Test("Bellows and Wim Hof power breaths share one rapid motif")
    func rapidBreathsMatch() {
        let bellows = beat(for: [Phase(kind: .inhale, duration: .seconds(1))])
        let wimHof = beat(for: [Phase(kind: .inhale, duration: .milliseconds(1500))])
        let style = WatchHapticStyle()

        #expect(style.pulses(for: bellows) == [.milliseconds(300)])
        #expect(style.pulses(for: wimHof) == [.milliseconds(300)])
    }

    @Test("A Wim Hof recovery breath returns to the shaped train")
    func recoveryStaysSlow() {
        let recovery = beat(for: [Phase(kind: .inhale, duration: .seconds(3))])

        #expect(WatchHapticStyle().pulses(for: recovery).count > 1)
    }

    @Test("Pulses leave both phase boundaries quiet")
    func leavesBoundaryRoom() throws {
        let inhale = beat(for: [fullInhale])
        let offsets = WatchHapticStyle().pulses(for: inhale)
        let first = try #require(offsets.first)
        let last = try #require(offsets.last)

        #expect(first >= .milliseconds(300))
        #expect(last < inhale.breathing - .milliseconds(300))
        #expect(zip(offsets.dropFirst(), offsets).allSatisfy { $0 > $1 })
    }

    @Test("A protocol seam shifts the whole opening window")
    func leavesRoomForASeam() throws {
        let inhale = beat(for: [fullInhale])
        let offsets = WatchHapticStyle().pulses(for: inhale, cueDelay: .milliseconds(350))

        #expect(try #require(offsets.first) >= .milliseconds(650))
        #expect(offsets.allSatisfy { $0 < inhale.breathing - .milliseconds(300) })
    }

    @Test("A phase with no pulse window keeps only its boundary cue")
    func shortPhaseHasNoPulses() {
        let short = beat(for: [Phase(kind: .inhale, duration: .milliseconds(600))])
        let offsets = WatchHapticStyle().pulses(for: short)

        #expect(offsets.isEmpty)
    }

    @Test("A slow top-up stays denser than an empty-lung inhale")
    func topUpStaysDense() throws {
        let phases = [
            Phase(kind: .inhale, duration: .seconds(4)),
            Phase(kind: .inhale, duration: .seconds(4)),
            Phase(kind: .exhale, duration: .seconds(5)),
        ]
        let opening = beat(for: phases)
        let topUp = beat(for: phases, at: 1)
        let style = WatchHapticStyle()
        let openingOffsets = style.pulses(for: opening)
        let topUpOffsets = style.pulses(for: topUp)

        let openingGap = try #require(gaps(of: openingOffsets).first)
        let topUpGap = try #require(gaps(of: topUpOffsets).first)
        #expect(topUpGap < openingGap)
    }

    @Test("The two standard holds remain distinct")
    func distinguishesHolds() throws {
        let style = WatchHapticStyle()
        let holdIn = try #require(style.holdTap(for: .holdIn))
        let holdOut = try #require(style.holdTap(for: .holdOut))

        #expect(holdIn > holdOut)
        #expect(style.holdTap(for: .complete) == nil)
    }

    @Test("Transient shapes never produce breath pulses")
    func transientHasNoPulses() {
        let hold = beat(for: [Phase(kind: .holdIn, duration: .seconds(4))])
        let offsets = WatchHapticStyle().pulses(for: hold)

        #expect(offsets.isEmpty)
    }
}

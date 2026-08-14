import OndKit
import Testing

/// The reduction from the phone's intensity curves to the wrist's four taps.
///
/// This was the watch app's main risk and it has not stopped being one: the
/// coarser vocabulary still has to make an inhale and an exhale feel
/// unmistakably different, and the simulator plays no haptics, so the mapping is
/// worth pinning where it can be.
@Suite("Watch cues")
struct WatchCueTests {
    @Test("A breath's direction survives the reduction")
    func distinguishesTheBreaths() {
        #expect(WatchCue(.inhale) == .rise)
        #expect(WatchCue(.exhale) == .fall)
        #expect(WatchCue(.inhale) != WatchCue(.exhale))
    }

    /// The phone makes a full-lung hold crisp and an empty-lung hold soft. The
    /// watch needs both identities intact to preserve that contrast.
    @Test("The two holds stay distinct")
    func distinguishesTheHolds() {
        #expect(WatchCue(.holdIn) == .holdIn)
        #expect(WatchCue(.holdOut) == .holdOut)
        #expect(WatchCue(.holdIn) != WatchCue(.holdOut))
    }

    /// The end-of-session cue is not something a phase can produce — feeling
    /// "finished" at the top of an inhale would be a lie about the plan.
    @Test("No phase is cued as a completion")
    func neverCuesAPhaseAsCompletion() {
        let phases: [PhaseKind] = [.inhale, .holdIn, .exhale, .holdOut]

        #expect(phases.allSatisfy { WatchCue($0) != .complete })
    }

    /// Both breaths carry sparse pulses; the holds stay discrete so stillness is felt as
    /// stillness, and completion is not a phase at all.
    @Test("Breaths sustain, holds and completion stay discrete")
    func sustainsTheBreathsOnly() {
        #expect(WatchCue.rise.sustains)
        #expect(WatchCue.fall.sustains)
        #expect(!WatchCue.holdIn.sustains)
        #expect(!WatchCue.holdOut.sustains)
        #expect(!WatchCue.complete.sustains)
    }

    @Test("Every seeded exercise uses the same phase vocabulary")
    func coversTheCatalogueSemantically() {
        let expected: [PhaseKind: WatchCue] = [
            .inhale: .rise,
            .holdIn: .holdIn,
            .exhale: .fall,
            .holdOut: .holdOut,
        ]
        var seen: Set<PhaseKind> = []

        for technique in SeededCatalogue.techniques {
            for beat in SessionTimeline(technique: technique).beats {
                seen.insert(beat.kind)
                #expect(WatchCue(beat.kind) == expected[beat.kind], "\(technique.slug)")
            }
        }

        #expect(seen == Set(expected.keys))
    }
}

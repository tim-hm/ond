import OndKit
import Testing

/// The wrist's rendering plan, pinned where a host can run it.
///
/// The exact gap values are wrist-judged and free to move; what these tests
/// hold still is the *shape* — the purr tails off, strength means density,
/// the inhale never ticks lighter than the exhale — because those are the
/// decisions a retune must not silently reverse.
@Suite("Watch haptic style")
struct WatchHapticStyleTests {
    private let phase = Duration.seconds(4)

    @Test("The purr tails off — every gap wider than the one before")
    func gapsWiden() {
        let offsets = WatchHapticStyle(strength: .standard).purr(over: phase)
        let gaps = zip(offsets.dropFirst(), offsets).map { $0 - $1 }

        #expect(offsets.count > 2)
        #expect(zip(gaps.dropFirst(), gaps).allSatisfy { $0 > $1 })
    }

    @Test("Every tick lands inside its phase, in order")
    func ticksStayInsideThePhase() {
        let offsets = WatchHapticStyle(strength: .strong).purr(over: phase)

        #expect(offsets.allSatisfy { $0 > .zero && $0 < phase })
        #expect(zip(offsets.dropFirst(), offsets).allSatisfy { $0 > $1 })
    }

    /// A wrist with no amplitude renders strength as density, so the ordering
    /// of tick counts is the setting working at all.
    @Test("Stronger is denser")
    func strengthIsDensity() {
        let counts = HapticStrength.allCases.map {
            WatchHapticStyle(strength: $0).purr(over: phase).count
        }

        #expect(counts == counts.sorted())
        #expect(Set(counts).count == counts.count)
    }

    /// The physiological sigh's second sip — 700 ms by default — is the whole
    /// point of that technique, so it must purr at every strength; a technique
    /// whose signature breath feels thinner than its first would be rendered
    /// backwards. Bellows breath's 700 ms dial floor rides on the same pin.
    @Test("The sigh's sip purrs at every strength")
    func sipStillPurrs() {
        for strength in HapticStrength.allCases {
            #expect(!WatchHapticStyle(strength: strength).purr(over: .milliseconds(700)).isEmpty)
        }
    }

    /// Below the catalogue's 500 ms floor there is no room between the
    /// announcing tap and a quiet hand-off; such a phase is left to its
    /// announcement.
    @Test("A phase below the catalogue floor plays its announcement alone")
    func shortPhasePurrsNotAtAll() {
        #expect(WatchHapticStyle(strength: .strong).purr(over: .milliseconds(450)).isEmpty)
    }

    /// Effort in, release out: whatever the strength, the way in must never
    /// feel lighter than the way out, or the wrist reads the breath backwards.
    @Test("The inhale never ticks lighter than the exhale")
    func inhaleCarriesTheWeight() {
        for strength in HapticStrength.allCases {
            let style = WatchHapticStyle(strength: strength)

            #expect(style.tap(for: .rise) >= style.tap(for: .fall))
        }
    }

    /// The reference feel: standard is what everything else is tuned against.
    @Test("Standard weighs the cues as tuned")
    func standardWeights() {
        let style = WatchHapticStyle(strength: .standard)

        #expect(style.tap(for: .rise) == .solid)
        #expect(style.tap(for: .fall) == .soft)
        #expect(style.tap(for: .mark) == .solid)
    }
}

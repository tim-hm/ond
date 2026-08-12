import OndKit
import Testing

/// The wrist's rendering plan, pinned where a host can run it.
///
/// The exact gap values are wrist-judged and free to move; what these tests
/// hold still is the *shape* — the inhale gathers and the exhale falls away,
/// strength means density, the inhale never ticks lighter than the exhale —
/// because those are the decisions a retune must not silently reverse.
@Suite("Watch haptic style")
struct WatchHapticStyleTests {
    /// The gaps between consecutive ticks, which is the purr's shape.
    private func gaps(of offsets: [Duration]) -> [Duration] {
        zip(offsets.dropFirst(), offsets).map { $0 - $1 }
    }

    /// The lengths production actually asks for, which are never round: what
    /// reaches `purr` is `Beat.breathing`, a phase already 25–75 ms short of
    /// its catalogue duration. A 4-second phase arriving as 4000 ms is the one
    /// case this suite must not be written against.
    private let breaths: [Duration] = [
        .milliseconds(3925), // box breathing's four seconds, turn gap removed
        .milliseconds(5430), // coherent breathing's five and a half
        .milliseconds(6925), // extended exhale's six
        .milliseconds(1450), // the sigh's first breath
        .milliseconds(960), // the sigh's sip at its default
    ]

    /// The differentiation the whole design rests on, and the exact shape of
    /// it: the exhale falls away, and the inhale is that same curve taken from
    /// the other end.
    ///
    /// Mirrored rather than merely opposite, because the two have to cost the
    /// wrist the same. Interpolating each direction separately looks equivalent
    /// and starves whichever one opens wide — a sip once ticked once on the way
    /// in against three times on the way back, which reads as the inhale having
    /// been turned down rather than as a breath changing direction.
    @Test("The exhale falls away, and the inhale is its mirror")
    func theInhaleMirrorsTheExhale() {
        for strength in HapticStrength.allCases {
            let style = WatchHapticStyle(strength: strength)

            for breath in breaths {
                let fall = gaps(of: style.purr(over: breath, for: .fall))
                let rise = gaps(of: style.purr(over: breath, for: .rise))

                #expect(
                    zip(fall.dropFirst(), fall).allSatisfy { $0 > $1 },
                    "\(strength) over \(breath) — the exhale stopped tailing off"
                )
                #expect(
                    rise == fall.reversed(),
                    "\(strength) over \(breath) — the inhale is not the exhale reversed"
                )
            }
        }
    }

    /// The exhale alone, here and below: the two directions share a stride list
    /// and therefore share their first tick, their last, and their count. That
    /// is `theInhaleMirrorsTheExhale`'s to hold, and checking it twice here
    /// would only be checking it again.
    @Test("Every tick lands inside its phase, in order")
    func ticksStayInsideThePhase() {
        let breath = Duration.milliseconds(3925)
        let offsets = WatchHapticStyle(strength: .strong).purr(over: breath, for: .fall)

        #expect(offsets.allSatisfy { $0 > .zero && $0 < breath })
        #expect(zip(offsets.dropFirst(), offsets).allSatisfy { $0 > $1 })
    }

    /// The style and `WatchCue.sustains` have to give one answer: a hold is one
    /// discrete vibration and completion is the system's own pattern, and
    /// neither has a phase to purr over. The player guards on `sustains` before
    /// it ever asks, so a disagreement here would show up only as a breath that
    /// went quiet on somebody's wrist.
    @Test("A cue that never sustains has no purr")
    func discreteCuesDoNotPurr() {
        let style = WatchHapticStyle(strength: .strong)

        #expect(style.purr(over: .milliseconds(3925), for: .mark).isEmpty)
        #expect(style.purr(over: .milliseconds(3925), for: .complete).isEmpty)
    }

    /// A wrist with no amplitude renders strength as density, so the ordering
    /// of tick counts is the setting working at all.
    @Test("Stronger is denser")
    func strengthIsDensity() {
        let counts = HapticStrength.allCases.map {
            WatchHapticStyle(strength: $0).purr(over: .milliseconds(3925), for: .fall).count
        }

        #expect(counts == counts.sorted())
        #expect(Set(counts).count == counts.count)
    }

    /// The physiological sigh's second sip is the whole point of that
    /// technique, so it must purr at every strength: a technique whose
    /// signature breath felt thinner than its first would be rendered
    /// backwards. Its second is 1 s by default, arriving here as 960 ms once
    /// the turn gap is taken off, and bellows breath's 700 ms dial floor rides
    /// on the same pin.
    @Test("The sigh's sip purrs at every strength")
    func sipStillPurrs() {
        for strength in HapticStrength.allCases {
            let style = WatchHapticStyle(strength: strength)

            #expect(!style.purr(over: .milliseconds(960), for: .rise).isEmpty)
        }
    }

    /// Under `lead` plus `tail` there is no room between the announcing tap and
    /// a quiet hand-off, so the breath is left to its announcement whichever
    /// way it was going. A sip dialled to the catalogue's 500 ms floor lands
    /// here once the turn gap is off it, which is a thin sip rendered honestly
    /// rather than a bug.
    @Test("A breath below the purr's floor plays its announcement alone")
    func shortPhasePurrsNotAtAll() {
        let style = WatchHapticStyle(strength: .strong)

        #expect(style.purr(over: .milliseconds(460), for: .rise).isEmpty)
        #expect(style.purr(over: .milliseconds(460), for: .fall).isEmpty)
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

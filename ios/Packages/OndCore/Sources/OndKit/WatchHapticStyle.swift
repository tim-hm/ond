/// The wrist's rendering plan at one strength: how densely a breath's purr
/// ticks, which way that density ramps, and how much weight each cue's tap
/// carries.
///
/// watchOS has no haptic intensity API, so strength on the wrist means density
/// and tap choice rather than amplitude — stronger packs the ticks closer and
/// picks heavier taps, gentler spreads them out and picks softer ones. The
/// phone scales its authored CoreHaptics patterns instead; the two renderers
/// share the `HapticStrength` selector and nothing else.
///
/// Modelled here rather than in the watch target so the curve and the weights
/// can be pinned by host tests. `WKHapticType` stays a watch-target word: this
/// type speaks only in `Tap` weights and offsets.
public struct WatchHapticStyle: Sendable, Equatable {
    /// The weight of one tap, named abstractly so the mapping onto a concrete
    /// `WKHapticType` stays in the watch target with the rest of the hardware
    /// vocabulary. Cases are declared lightest to heaviest — the synthesized
    /// `Comparable` is what "never lighter than" means.
    public enum Tap: Sendable, Comparable {
        /// The faintest tick there is.
        case soft
        /// One solid tap.
        case solid
        /// The heaviest thing that still reads as a tap, not an alert.
        case prominent
    }

    private let strength: HapticStrength

    public init(strength: HapticStrength) {
        self.strength = strength
    }

    /// The weight each cue's tap carries at this strength.
    ///
    /// For a breath this is the purr's tick, and the inhale is never lighter
    /// than the exhale — effort in, release out — which is also how the phone's
    /// patterns and the orb read the breath. PIV's own tuning recommends the
    /// reverse, an exhale-weighted pattern; here the direction is carried by
    /// the purr's shape instead (see ``purr(over:for:)``), which leaves the tap
    /// free to follow the effort. Worth settling on a wrist rather than on
    /// paper. For a hold it is the one vibration that marks stillness.
    /// `.complete` keeps the system's own completion pattern; its weight here
    /// is never played.
    public func tap(for cue: WatchCue) -> Tap {
        switch cue {
        case .rise: weights.rise
        case .fall: weights.fall
        case .mark: weights.mark
        case .complete: .prominent
        }
    }

    private struct Weights {
        let rise: Tap
        let fall: Tap
        let mark: Tap
    }

    /// One row per strength, so a wrist-tuning pass edits a whole feel at
    /// once instead of three scattered switch arms.
    private var weights: Weights {
        switch strength {
        case .gentle: Weights(rise: .soft, fall: .soft, mark: .solid)
        case .standard: Weights(rise: .solid, fall: .soft, mark: .solid)
        case .strong: Weights(rise: .solid, fall: .solid, mark: .prominent)
        }
    }

    /// Every tick of a breath's purr, as offsets from the phase's start.
    ///
    /// The two breaths run one curve in opposite directions. The inhale's gaps
    /// narrow as the lungs fill, so the purr gathers into the top of the
    /// breath; the exhale's widen, so the taps fall away from it and thin out
    /// into empty. Across a whole cycle that is a single arc, densest at the
    /// turn — and the direction is legible mid-phase, from the wrist alone,
    /// instead of only at the tap that opened it.
    ///
    /// That the two differ in *shape* rather than only in weight is the pacing
    /// literature's finding and not this file's taste. Miri et al.'s
    /// vibrotactile pacer (PIV, ACM TOCHI 27(1), 2020, doi:10.1145/3365107) is
    /// built on biphasic patterns — the stretch cueing the inhale deliberately
    /// feels unlike the stretch cueing the exhale — and of the three ways they
    /// separated the phases, the one they recommend varies the vibration's
    /// frequency rather than its amplitude. That recommendation costs nothing
    /// here: watchOS offers no amplitude to vary, so density is the only axis
    /// this wrist has.
    ///
    /// Offsets rather than gaps so the player can sleep to absolute deadlines —
    /// a wake-up the system delayed must not stretch the train. The first tick
    /// waits out `lead` so the announcing tap is felt whole, and the last lands
    /// before `tail` so the next cue arrives on a quiet wrist; a phase too
    /// short for both plays its announcement alone, and a cue that never
    /// sustains has no purr to schedule.
    ///
    /// The curve is walked once, in the exhale's direction, and the inhale
    /// takes the same strides in reverse. Walking each direction on its own
    /// interpolation looks equivalent and is not: a greedy stride fits a
    /// different number of ticks depending on which end it starts from, and it
    /// starves the direction that opens wide. Over a sigh's one-second sip that
    /// came out as a single tick on the way in against three on the way back —
    /// which reads as the inhale having been turned down, not as a breath
    /// changing direction.
    public func purr(over duration: Duration, for cue: WatchCue) -> [Duration] {
        guard cue.sustains else { return [] }

        let end = duration - Self.tail
        let window = end - Self.lead
        guard window > .zero else { return [] }

        var strides: [Duration] = []
        var offset = Self.lead
        while true {
            let progress = (offset - Self.lead) / window
            let stride = gaps.full * (1 - progress) + gaps.empty * progress
            guard offset + stride < end else { break }
            strides.append(stride)
            offset += stride
        }

        var offsets = [Self.lead]
        var running = Self.lead
        for stride in cue == .rise ? Array(strides.reversed()) : strides {
            running += stride
            offsets.append(running)
        }
        return offsets
    }

    /// The purr's cadence at the top of the breath and at the bottom of it —
    /// one curve the two phases each take half of, tightest with the lungs
    /// full and loosest with them empty. Strength is mostly density on a wrist
    /// with no amplitude, so these move together with it. Judged on a wrist,
    /// not derived.
    private var gaps: (full: Duration, empty: Duration) {
        switch strength {
        case .gentle: (.milliseconds(110), .milliseconds(340))
        case .standard: (.milliseconds(80), .milliseconds(300))
        case .strong: (.milliseconds(60), .milliseconds(240))
        }
    }

    /// Room for the announcing directional tap to finish before the first
    /// tick, so the rise or fall is felt before the purr begins.
    ///
    /// Together with `tail` this sets the shortest breath that purrs at all,
    /// and the figure is easy to state a little too generously. The two sum to
    /// 500 ms and the window has to be wider than that, not equal to it — and
    /// what arrives here is `Beat.breathing`, already 25–75 ms short of the
    /// phase (`SessionTurnGap`). So a sip dialled to the catalogue's 500 ms
    /// floor plays its announcement alone; its 1 s default is the one that has
    /// to purr, and does.
    private static let lead: Duration = .milliseconds(250)

    /// The purr stops this far before the phase ends so the next phase's cue
    /// stands alone instead of arriving mid-vibration.
    private static let tail: Duration = .milliseconds(250)
}

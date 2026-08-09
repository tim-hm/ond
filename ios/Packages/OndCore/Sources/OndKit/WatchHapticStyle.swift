/// The wrist's rendering plan at one strength: how densely a breath's purr
/// ticks, and how much weight each cue's tap carries.
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
    /// than the exhale — effort in, release out — so mid-phase the wrist knows
    /// which way the air is moving. For a hold it is the one vibration that
    /// marks stillness. `.complete` keeps the system's own completion pattern;
    /// its weight here is never played.
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
    /// The gap widens linearly from opening to closing across the phase, so
    /// the vibration is densest at the turn of the breath and tails off as the
    /// phase ends. Offsets rather than gaps so the player can sleep to
    /// absolute deadlines — a wake-up the system delayed must not stretch the
    /// train. The first tick waits out `lead` so the announcing tap is felt
    /// whole, and the last lands before `tail` so the next cue arrives on a
    /// quiet wrist; a phase too short for both plays its announcement alone.
    public func purr(over duration: Duration) -> [Duration] {
        let end = duration - Self.tail
        let window = end - Self.lead
        guard window > .zero else { return [] }

        let (opening, closing) = gaps
        var offsets: [Duration] = []
        var offset = Self.lead
        while offset < end {
            offsets.append(offset)
            let progress = (offset - Self.lead) / window
            offset += opening * (1 - progress) + closing * progress
        }
        return offsets
    }

    /// The purr's cadence at the turn of the breath and by the end of the
    /// phase. Strength is mostly density on a wrist with no amplitude, so
    /// these move together with it. Judged on a wrist, not derived.
    private var gaps: (opening: Duration, closing: Duration) {
        switch strength {
        case .gentle: (.milliseconds(110), .milliseconds(340))
        case .standard: (.milliseconds(80), .milliseconds(300))
        case .strong: (.milliseconds(60), .milliseconds(240))
        }
    }

    /// Room for the announcing directional tap to finish before the first
    /// tick, so the rise or fall is felt before the purr begins.
    ///
    /// Together with `tail` this sets the shortest phase that purrs at all:
    /// 500 ms, which is the catalogue's true floor (the physiological sigh's
    /// sip dials down to it). The sip's 700 ms default must land above it —
    /// a technique whose point is the second sip should not feel thinner
    /// than the first breath.
    private static let lead: Duration = .milliseconds(250)

    /// The purr stops this far before the phase ends so the next phase's cue
    /// stands alone instead of arriving mid-vibration.
    private static let tail: Duration = .milliseconds(250)
}

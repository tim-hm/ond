/// The wrist's rendering plan for the phone-authored haptic shape.
///
/// watchOS offers predefined patterns but no haptic intensity API. A breath's
/// amplitude envelope therefore becomes click density: stronger parts place
/// neutral clicks closer together, while softer parts leave more air between
/// them. Strength changes that density and the two hold cues without changing
/// the authored shape shared with the phone.
public struct WatchHapticStyle: Sendable, Equatable {
    /// The weight of a discrete hold cue, named without WatchKit so the mapping
    /// onto `WKHapticType` stays in the watch target.
    public enum Tap: Sendable, Comparable {
        /// The system's neutral click.
        case soft
        /// A solid boundary cue.
        case solid
        /// The most prominent non-alerting boundary cue available.
        case prominent
    }

    private let strength: HapticStrength

    public init(strength: HapticStrength) {
        self.strength = strength
    }

    /// The nearest watch weight for one of the shared transient phase shapes.
    ///
    /// The full-lung hold stays heavier than the empty-lung hold at every
    /// strength, preserving the phone's crisp 0.9 tap against its soft 0.45 tap.
    /// Breath and completion cues have dedicated system patterns and return nil.
    ///
    /// - Parameter cue: The phase-boundary cue to resolve.
    public func holdTap(for cue: WatchCue) -> Tap? {
        switch (strength, cue) {
        case (.strong, .holdIn): .prominent
        case (.strong, .holdOut): .solid
        case (.gentle, .holdIn), (.standard, .holdIn): .solid
        case (.gentle, .holdOut), (.standard, .holdOut): .soft
        case (_, .rise), (_, .fall), (_, .complete): nil
        }
    }

    /// Neutral-click deadlines that approximate a shared continuous shape.
    ///
    /// Offsets are measured from the beat boundary, not from the directional
    /// cue. That keeps a protocol seam's delayed cue and all its clicks inside
    /// the original phase. The first click waits 300 ms after the cue and the
    /// final 300 ms stays quiet for an unambiguous hand-off to the next phase.
    ///
    /// The current authored intensity selects a gap between this strength's
    /// empty and full bounds. Sampling the envelope at each click preserves
    /// partial movements: the physiological sigh's second inhale stays near the
    /// dense end because its shared shape starts almost full.
    ///
    /// - Parameters:
    ///   - duration: The beat's breathing span, with its turn gap removed.
    ///   - shape: The phone-authored continuous shape to translate.
    ///   - cueDelay: Time reserved for a stage or round seam before the phase cue.
    /// - Returns: Absolute offsets from the beat boundary, in ascending order.
    public func pulses(
        over duration: Duration,
        shape: SessionHapticShape,
        cueDelay: Duration = .zero
    ) -> [Duration] {
        guard case let .continuous(startIntensity, endIntensity, _) = shape else { return [] }

        let first = cueDelay + Self.lead
        let end = duration - Self.tail
        guard first < end else { return [] }

        var offsets: [Duration] = []
        var offset = first
        while offset < end {
            offsets.append(offset)
            let progress = offset / duration
            let intensity = Double(startIntensity)
                + (Double(endIntensity) - Double(startIntensity)) * progress
            let level = Self.level(ofAuthoredIntensity: intensity)
            offset += gaps.empty * (1 - level) + gaps.full * level
        }
        return offsets
    }

    /// The spacing at the phone envelope's strongest and softest authored
    /// values. Wider ranges make the strength setting perceptible without
    /// changing the fixed amplitude of watchOS's `.click` pattern.
    private var gaps: (full: Duration, empty: Duration) {
        switch strength {
        case .gentle: (.milliseconds(600), .milliseconds(1000))
        case .standard: (.milliseconds(500), .milliseconds(850))
        case .strong: (.milliseconds(425), .milliseconds(700))
        }
    }

    /// Re-bases the full set of phone-authored continuous intensities onto the
    /// watch's 0...1 density axis. The exhale's 0.08 is its quietest point and
    /// the inhale's 0.85 its strongest.
    private static func level(ofAuthoredIntensity intensity: Double) -> Double {
        min(max((intensity - 0.08) / (0.85 - 0.08), 0), 1)
    }

    /// Room for the directional cue to finish before the first neutral click.
    private static let lead: Duration = .milliseconds(300)

    /// Quiet room before the next phase boundary.
    private static let tail: Duration = .milliseconds(300)
}

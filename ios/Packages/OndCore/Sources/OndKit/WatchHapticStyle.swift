/// The wrist's rendering plan for the phone-authored haptic shape.
///
/// watchOS offers predefined patterns but no haptic intensity API. A breath's
/// amplitude envelope therefore becomes pulse density: stronger parts place
/// pulses closer together, while softer parts leave more air between
/// them. The fixed cadence is the watch's standard translation of the shape
/// shared with the phone.
public struct WatchHapticStyle: Sendable, Equatable {
    /// The weight of a discrete hold cue, named without WatchKit so the mapping
    /// onto `WKHapticType` stays in the watch target.
    public enum Tap: Sendable, Comparable {
        /// The system's neutral click.
        case soft
        /// A solid boundary cue.
        case solid
    }

    /// Creates the fixed Standard renderer used by every watch session.
    public init() {}

    /// The standard watch weight for one of the shared transient phase shapes.
    ///
    /// The full-lung hold stays heavier than the empty-lung hold, preserving
    /// the phone's crisp 0.9 tap against its soft 0.45 tap.
    /// Breath and completion cues have dedicated system patterns and return nil.
    ///
    /// - Parameter cue: The phase-boundary cue to resolve.
    public func holdTap(for cue: WatchCue) -> Tap? {
        switch cue {
        case .holdIn: .solid
        case .holdOut: .soft
        case .rise, .fall, .complete: nil
        }
    }

    /// Breath-pulse deadlines that approximate a shared continuous shape.
    ///
    /// Offsets are measured from the beat boundary, not from the directional
    /// cue. That keeps a protocol seam's delayed cue and all its pulses inside
    /// the original phase. The first pulse waits 300 ms after the cue and the
    /// final 300 ms stays quiet for an unambiguous hand-off to the next phase.
    ///
    /// The current authored intensity selects a gap between the standard
    /// empty and full bounds. Sampling the envelope at each pulse preserves
    /// partial movements: the physiological sigh's second inhale stays near the
    /// dense end because its shared shape starts almost full.
    ///
    /// An individual phase shorter than two seconds uses one follow-on pulse.
    /// That gives Bellows and Wim Hof power breaths the same motif despite their
    /// different authored tempos, while a longer recovery breath keeps the
    /// shaped train.
    ///
    /// - Parameters:
    ///   - beat: The laid-out phase and its phone-authored shape.
    ///   - cueDelay: Time reserved for a stage or round seam before the phase cue.
    /// - Returns: Absolute offsets from the beat boundary, in ascending order.
    public func pulses(
        for beat: SessionTimeline.Beat,
        cueDelay: Duration = .zero
    ) -> [Duration] {
        let shape = SessionHapticShape(beat: beat)
        guard case let .continuous(startIntensity, endIntensity, _) = shape else { return [] }

        let first = cueDelay + Self.lead
        let duration = beat.breathing
        let end = duration - Self.tail
        guard first < end else { return [] }
        if beat.duration < Stage.fastPhase {
            return [first]
        }

        var offsets: [Duration] = []
        var offset = first
        while offset < end {
            offsets.append(offset)
            let progress = offset / duration
            let intensity = Double(startIntensity)
                + (Double(endIntensity) - Double(startIntensity)) * progress
            let level = Self.level(ofAuthoredIntensity: intensity)
            offset += Self.gaps.empty * (1 - level) + Self.gaps.full * level
        }
        return offsets
    }

    /// The standard spacing at the phone envelope's strongest and softest
    /// authored values.
    private static let gaps = (full: Duration.milliseconds(500), empty: Duration.milliseconds(850))

    /// Re-bases the full set of phone-authored continuous intensities onto the
    /// watch's 0...1 density axis. The exhale's 0.08 is its quietest point and
    /// the inhale's 0.85 its strongest.
    private static func level(ofAuthoredIntensity intensity: Double) -> Double {
        min(max((intensity - 0.08) / (0.85 - 0.08), 0), 1)
    }

    /// Room for the directional cue to finish before the first breath pulse.
    private static let lead: Duration = .milliseconds(300)

    /// Quiet room before the next phase boundary.
    private static let tail: Duration = .milliseconds(300)
}

/// The wrist's rendering plan for the phone-authored haptic shape. watchOS
/// has no haptic intensity API, so a breath's amplitude envelope becomes
/// pulse density: stronger parts place pulses closer together.
public struct WatchHapticStyle: Sendable, Equatable {
    public enum Preview: String, Sendable, CaseIterable, Identifiable {
        case current, boundary, sparse
        public var id: Self {
            self
        }

        public var title: String {
            switch self {
            case .current: "Current"
            case .boundary: "Boundaries only"
            case .sparse: "Fewer pulses"
            }
        }
    }

    private let preview: Preview
    /// The weight of a discrete hold cue, named without WatchKit so the mapping
    /// onto `WKHapticType` stays in the watch target.
    public enum Tap: Sendable, Comparable {
        /// The system's neutral click.
        case soft
        /// A solid boundary cue.
        case solid
    }

    public init(preview: Preview = .current) {
        self.preview = preview
    }

    /// The full-lung hold stays heavier than the empty-lung hold, preserving
    /// the phone's crisp 0.9 tap against its soft 0.45. Breath and completion
    /// cues have dedicated system patterns and return nil.
    public func holdTap(for cue: WatchCue) -> Tap? {
        switch cue {
        case .holdIn: .solid
        case .holdOut: .soft
        case .rise, .fall, .complete: nil
        }
    }

    /// Breath-pulse deadlines approximating the shared continuous shape.
    /// Offsets are measured from the beat boundary, not the directional cue,
    /// so a seam's delayed cue and all its pulses stay inside the phase. The
    /// envelope is sampled at each pulse, and a phase under two seconds gets
    /// one follow-on pulse. Returns ascending offsets from the beat boundary.
    public func pulses(
        for beat: SessionTimeline.Beat,
        cueDelay: Duration = .zero
    ) -> [Duration] {
        guard preview != .boundary,
              let envelope = SessionHapticShape(beat: beat).envelope else { return [] }

        let first = envelope.span.lowerBound + cueDelay
        let duration = beat.breathing
        guard first < envelope.span.upperBound else { return [] }
        if beat.duration < Stage.fastPhase {
            return [first]
        }

        var offsets: [Duration] = []
        var offset = first
        while offset < envelope.span.upperBound {
            offsets.append(offset)
            let progress = offset / duration
            let intensity = Double(envelope.startIntensity)
                + (Double(envelope.endIntensity) - Double(envelope.startIntensity)) * progress
            let level = Self.level(ofAuthoredIntensity: intensity)
            let gap = Self.gaps.empty * (1 - level) + Self.gaps.full * level
            offset += gap * (preview == .sparse ? 1.8 : 1)
        }
        return offsets
    }

    public func remainingPulses(
        for beat: SessionTimeline.Beat,
        at elapsed: Duration
    ) -> [Duration] {
        let offset = max(.zero, elapsed - beat.start)
        let delay: Duration = beat.opensStage ? .milliseconds(350) : .zero
        return pulses(for: beat, cueDelay: delay).compactMap { pulse in
            pulse > offset ? pulse - offset : nil
        }
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
}

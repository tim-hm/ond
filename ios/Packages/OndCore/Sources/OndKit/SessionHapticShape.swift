/// The authored tactile shape of one session phase, before a device renders
/// it. The phone can play these values directly through Core Haptics. The
/// watch cannot vary amplitude or sharpness, so it translates a continuous
/// shape into pulse density and a transient shape into the nearest system
/// cue. One source keeps those renderers from describing different breaths.
public enum SessionHapticShape: Sendable, Equatable {
    /// A phase-long event whose intensity travels from `startIntensity` at
    /// the phase boundary to `endIntensity` as breathing movement ends, with
    /// a fixed tactile edge.
    case continuous(startIntensity: Float, endIntensity: Float, sharpness: Float)

    /// A momentary phase-boundary event.
    ///
    /// - Parameters:
    ///   - intensity: The authored force of the tap.
    ///   - sharpness: The authored tactile edge of the tap.
    case transient(intensity: Float, sharpness: Float)

    /// Resolves the device-independent shape for a laid-out session beat.
    /// A breath's endpoints come from its actual lung fullness, not only its
    /// direction — preserving a stacked inhale such as the physiological
    /// sigh's sip, which starts almost full and adds only the final tenth.
    public init(beat: SessionTimeline.Beat) {
        switch beat.kind {
        case .inhale:
            self = .continuous(
                startIntensity: Self.inhaleIntensity(at: beat.startFullness),
                endIntensity: Self.inhaleIntensity(at: beat.endFullness),
                sharpness: 0.3
            )
        case .exhale:
            self = .continuous(
                startIntensity: Self.exhaleIntensity(at: beat.startFullness),
                endIntensity: Self.exhaleIntensity(at: beat.endFullness),
                sharpness: 0.1
            )
        case .holdIn:
            self = .transient(intensity: 0.9, sharpness: 0.8)
        case .holdOut:
            self = .transient(intensity: 0.45, sharpness: 0.1)
        }
    }

    private static func inhaleIntensity(at fullness: Double) -> Float {
        authoredIntensity(at: fullness, empty: 0.12, full: 0.85)
    }

    private static func exhaleIntensity(at fullness: Double) -> Float {
        authoredIntensity(at: fullness, empty: 0.08, full: 0.8)
    }

    private static func authoredIntensity(at fullness: Double, empty: Float, full: Float) -> Float {
        let level = SessionTimeline.Beat.level(ofFullness: fullness)
        return empty + (full - empty) * Float(level)
    }
}

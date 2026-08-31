/// The wrist's haptic vocabulary: five cues you can tell apart with the
/// screen dark. watchOS has no CoreHaptics, so a breath is sparse pulses
/// across its phase and each hold one discrete cue — direction and still
/// point must stay legible even so. Shared here so a host test can pin it;
/// `WKHapticType` is named only in the watch target.
public enum WatchCue: Sendable, Equatable {
    /// The lungs filling.
    case rise
    /// The lungs emptying.
    case fall
    /// Stillness with full lungs.
    case holdIn
    /// Stillness with empty lungs.
    case holdOut
    /// The session reaching its end, as opposed to being ended.
    case complete
}

public extension WatchCue {
    /// Whether the cue carries sparse pulses across its whole phase rather than
    /// only a discrete boundary tap.
    ///
    /// Both breaths sustain through `WatchHapticStyle.pulses`; the holds stay
    /// discrete, which keeps them legible as stillness between moving phases.
    var sustains: Bool {
        switch self {
        case .rise, .fall: true
        case .holdIn, .holdOut, .complete: false
        }
    }

    /// The cue a phase boundary earns.
    ///
    /// Never `.complete`: that one marks the end of the plan, not the start of a
    /// phase, and nothing you are about to breathe should feel like finishing.
    init(_ kind: PhaseKind) {
        self = switch kind {
        case .inhale: .rise
        case .exhale: .fall
        case .holdIn: .holdIn
        case .holdOut: .holdOut
        }
    }
}

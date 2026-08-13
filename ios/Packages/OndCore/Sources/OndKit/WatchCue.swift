/// The wrist's whole haptic vocabulary: five cues you can tell apart with your
/// eyes shut.
///
/// watchOS has no CoreHaptics, so a phase cannot be *shaped* the way the phone
/// shapes it — a breath is rendered as sparse clicks across its phase, and each
/// hold is one discrete cue. What survives that reduction is a decision rather
/// than an API detail: both breath direction and which still point it reached
/// must remain legible with the screen dark.
///
/// The decision lives here, in the shared module, so it can be pinned by a host
/// test; `WKHapticType` is named only in the watch target, which is the half
/// that cannot be tested without a wrist.
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
    /// Whether the cue carries sparse clicks across its whole phase rather than
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

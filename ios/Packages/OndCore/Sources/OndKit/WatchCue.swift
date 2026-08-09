/// The wrist's whole haptic vocabulary: four cues you can tell apart with your
/// eyes shut.
///
/// watchOS has no CoreHaptics, so a phase cannot be *shaped* the way the phone
/// shapes it — a breath is rendered as a train of ticks across its phase
/// (``sustains``), a hold as one discrete tap whose weight comes from
/// `WatchHapticStyle`. What survives that reduction is a decision rather than
/// an API detail: an inhale and an exhale
/// must stay unmistakably different, and the two holds may share a tap because
/// which hold you are in is never in doubt when you are in it.
///
/// The decision lives here, in the shared module, so it can be pinned by a host
/// test; `WKHapticType` is named only in the watch target, which is the half
/// that cannot be tested without a wrist.
public enum WatchCue: Sendable, Equatable {
    /// The lungs filling.
    case rise
    /// The lungs emptying.
    case fall
    /// A boundary with no direction to it — either hold.
    case mark
    /// The session reaching its end, as opposed to being ended.
    case complete
}

public extension WatchCue {
    /// Whether the cue is rendered as a sustained run of ticks across its
    /// whole phase rather than a discrete tap.
    ///
    /// Both breaths sustain: a vibration that lasts as long as the breath is
    /// the wrist's closest analogue to the phone's shaped patterns. The holds
    /// stay discrete, which is what keeps them legible as stillness between
    /// two moving phases.
    var sustains: Bool {
        switch self {
        case .rise, .fall: true
        case .mark, .complete: false
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
        case .holdIn, .holdOut: .mark
        }
    }
}

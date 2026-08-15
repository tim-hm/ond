/// What the session's breath guide draws.
///
/// `sphere` is the default and the one the app was built around: a soft disc
/// swelling and shrinking with the breath, which is the whole instruction.
/// `ring` fills its arc over the phase instead of scaling — the rendering
/// Reduce Motion forces, offered to anyone who reads a filling gauge faster
/// than a growing body.
///
/// An enum rather than a toggle because the guide is the app's one screen
/// worth iterating on: a third rendering should be a case and a `switch` arm,
/// not a redesign of the setting. A tumbling cage of rings lived here for a
/// while and did not survive contact with a real breath; git holds it.
///
/// The raw value is a stored key — see `Passage` for the rule.
public enum BreathVisualStyle: String, Sendable, CaseIterable, Identifiable {
    case sphere
    case ring

    public var id: Self {
        self
    }

    public var title: String {
        switch self {
        case .sphere: "Sphere"
        case .ring: "Ring"
        }
    }
}

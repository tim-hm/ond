/// What the session's breath guide draws. `sphere` swells and shrinks with
/// the breath; `ring` fills its arc over the phase — the rendering Reduce
/// Motion forces, offered to anyone who reads a gauge faster than a growing
/// body. An enum rather than a toggle so a third rendering is a case and a
/// `switch` arm. The raw value is a stored key — see `Passage` for the rule.
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

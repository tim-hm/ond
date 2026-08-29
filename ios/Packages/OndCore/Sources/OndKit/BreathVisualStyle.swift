/// What the session's breath guide draws. `scaling` swells and shrinks the
/// core with the breath; `sweeping` puts an arc in its place that fills over
/// the phase, so nothing scales — which is what Reduce Motion selects. The
/// Dynamic Island draws the same inversion with a core parked behind its own
/// ring. An enum rather than a toggle so a third rendering is a `switch` arm.
public enum BreathVisualStyle: String, Sendable, CaseIterable, Identifiable {
    /// The raw values are the keys these were stored under when the two
    /// renderings were called Sphere and Ring. They are a person's saved
    /// choice — see `Passage` for the rule — so only the words moved.
    case scaling = "sphere"
    case sweeping = "ring"

    public var id: Self {
        self
    }

    public var title: String {
        switch self {
        case .scaling: "Scaling"
        case .sweeping: "Sweeping"
        }
    }

    /// The rendering a session actually draws. Reduce Motion selects Sweeping
    /// for everyone rather than taking the choice away: it is the one
    /// rendering where the core does not scale, so honouring the setting and
    /// honouring the choice are the same code path — and Settings can state
    /// the value a person was moved to.
    public func drawn(underReduceMotion reduceMotion: Bool) -> BreathVisualStyle {
        reduceMotion ? .sweeping : self
    }
}

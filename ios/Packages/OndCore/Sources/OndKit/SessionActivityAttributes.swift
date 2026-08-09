#if os(iOS)
    import ActivityKit

    /// What a running session tells the system about itself once, at the start —
    /// the half of the Live Activity that cannot change while it is on screen.
    ///
    /// Only the two facts the surface needs to draw itself: what is being
    /// practised, and which accent it is drawn in. The goal rather than the
    /// colour, because `OndUI` knows nothing about a technique and the mapping
    /// onto an accent belongs to `OndStyle` — a `Color` on the wire here would
    /// invert that and put the palette inside a payload.
    ///
    /// `ContentState` is a plain `SessionPresence` rather than a type nested in
    /// here, which is what keeps the moving half of this surface testable on the
    /// host: `ActivityAttributes` is unavailable on macOS, and a nested state
    /// would take every calculation in it out of reach of the suite.
    ///
    /// `#if os(iOS)` rather than `canImport(ActivityKit)`: the macOS SDK ships
    /// the framework with every symbol in it marked unavailable, so the import
    /// succeeds and the file then fails to compile.
    /// `Sendable` explicitly, which `ActivityAttributes` does not imply: the
    /// value is handed to the task that owns the Activity, and a public struct
    /// gets no implicit conformance to lean on.
    public struct SessionActivityAttributes: ActivityAttributes, Sendable {
        public typealias ContentState = SessionPresence

        public let techniqueName: String
        public let goal: TechniqueGoal
        /// Whether this session keeps running with the app away — which decides
        /// whether the lock screen may offer to resume it. See
        /// ``SessionModel/followsYouOut``.
        public let followsYouOut: Bool

        @MainActor
        public init(of session: SessionModel) {
            techniqueName = session.technique.name
            goal = session.technique.goal
            followsYouOut = session.followsYouOut
        }
    }
#endif

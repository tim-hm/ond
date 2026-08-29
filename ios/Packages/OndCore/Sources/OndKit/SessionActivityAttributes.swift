#if os(iOS)
    import ActivityKit

    /// The static half of the Live Activity, fixed at request time. It carries the
    /// goal, not a `Color`: the accent mapping belongs to `OndStyle`. `ContentState`
    /// is a plain `SessionPresence`, which keeps it testable on macOS, where
    /// `ActivityAttributes` is unavailable. `#if os(iOS)`, not `canImport`: the macOS
    /// SDK marks every symbol unavailable, so the import succeeds but compiling fails.
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
            techniqueName = session.title
            goal = session.technique.goal
            followsYouOut = session.followsYouOut
        }
    }
#endif

public extension TechniqueGoal {
    /// The goals `techniques` can actually serve, in the fixed calm-first order
    /// of the enum.
    ///
    /// Ordered by the enum rather than by the catalogue so nothing reshuffles
    /// under a person who has learned where sleep sits. The techniques list's
    /// sections are what read it today, and it sits on the type rather than in
    /// that view so the next surface to group a catalogue cannot arrive at its
    /// own order — a drift nothing but somebody's memory would catch.
    static func present(in techniques: [Technique]) -> [TechniqueGoal] {
        allCases.filter { goal in
            techniques.contains { $0.goal == goal }
        }
    }
}

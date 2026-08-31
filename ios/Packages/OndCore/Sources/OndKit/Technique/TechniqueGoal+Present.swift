public extension TechniqueGoal {
    /// The goals `techniques` can serve, in the enum's fixed calm-first order
    /// rather than the catalogue's, so nothing reshuffles under a person who
    /// has learned where sleep sits. On the type so the next surface to group
    /// a catalogue cannot arrive at its own order.
    static func present(in techniques: [Technique]) -> [TechniqueGoal] {
        allCases.filter { goal in
            techniques.contains { $0.goal == goal }
        }
    }
}

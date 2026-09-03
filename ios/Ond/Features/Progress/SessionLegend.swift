import OndKit

/// What names and marks a logged session: every exercise this device can still
/// resolve, curated and authored together. Built where the log is drawn, so
/// the tab and the full history name the same session the same way.
struct SessionLegend {
    /// A missing exercise leaves its historical slug visible instead of hiding
    /// the session that outlived it.
    let names: [TechniqueSlug: String]

    /// What each resolvable session was for. A session whose exercise is gone
    /// keeps its row and draws a neutral dot: a guessed goal would be a claim
    /// about practice nobody made.
    let goals: [TechniqueSlug: TechniqueGoal]

    /// Read from the two models that hold exercises, which are the screen's,
    /// so the whole legend is folded once a draw rather than once a row.
    @MainActor
    init(catalogue: TechniqueListModel, own: UserTechniqueModel) {
        let catalogued = if case let .loaded(techniques) = catalogue.state {
            techniques
        } else {
            [Technique]()
        }
        let techniques = catalogued + own.techniques

        names = Dictionary(techniques.map { ($0.slug, $0.name) }) { _, latest in latest }
        goals = techniques.reduce(into: [TechniqueSlug: TechniqueGoal]()) { result, technique in
            result[technique.slug] = technique.goal
        }
    }
}

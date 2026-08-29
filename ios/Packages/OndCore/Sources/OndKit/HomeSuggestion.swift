import Foundation

/// The one context rule Home and the reminders are built on: which technique
/// a goal resolves to. Deliberately the modest, on-device placeholder for
/// M6's personalisation — fixed rules, no learning. Pure on purpose, so the
/// rule is testable against any history.
public enum HomeSuggestion {
    /// Which technique to offer for `goal`: the one this person last used
    /// towards it, or the catalogue's first for it; falls back across goals
    /// only when the catalogue has nothing for this one. **"Last" is read off
    /// the dates, never the array's order** — callers hand histories sorted
    /// both ways, and an order-dependent rule breaks silently on the next one.
    public static func technique(
        for goal: TechniqueGoal,
        techniques: [Technique],
        history: [SessionRecord]
    ) -> Technique? {
        let forGoal = techniques.filter { $0.goal == goal }
        let slugs = Set(forGoal.map(\.slug))

        let latest = history
            .filter { slugs.contains($0.techniqueSlug) }
            .max { $0.startedAt < $1.startedAt }

        let theirs = latest.flatMap { record in
            forGoal.first { $0.slug == record.techniqueSlug }
        }

        return theirs ?? forGoal.first ?? techniques.first
    }
}

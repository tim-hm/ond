import Foundation

/// The context rules home is built on: which goal an hour of the day reaches
/// for, and which technique a goal resolves to.
///
/// Deliberately the modest, on-device placeholder for M6's personalisation —
/// fixed rules, no learning. Pure on purpose: the hour arrives as an argument
/// rather than a clock read, so every rule is testable at any time of day.
public enum HomeSuggestion {
    /// The goal a given local hour reaches for. Boundaries are round numbers,
    /// not science: mornings wake up, working hours focus, evenings wind
    /// down, and everything after ten is about sleep.
    public static func goal(forHour hour: Int) -> TechniqueGoal {
        switch hour {
        case 5 ..< 11: .energy
        case 11 ..< 17: .focus
        case 17 ..< 22: .calm
        default: .sleep
        }
    }

    /// Which technique to offer for `goal`: the one this person last used
    /// towards it, or the catalogue's first for it.
    ///
    /// Preferring their own is the whole of the personalisation here — a
    /// person who always reaches for 4-7-8 at night should not have to walk
    /// past coherent breathing to find it. Falls back across goals only when
    /// the catalogue has nothing for this one, so a caller always has something
    /// to begin.
    ///
    /// **Which session is "last" is read off the dates, never off the array's
    /// order.** It was `history.reversed()…first` for as long as the only caller
    /// handed it a store's own oldest-first list; the caller that replaced it
    /// hands over `JourneyModel.history`, which is newest-first, and the same
    /// expression then answered with the *first* thing this person ever
    /// breathed. A rule about "last used" that turns on how a caller happens to
    /// sort is a rule that breaks silently on the next caller.
    ///
    /// - Parameter history: every session on this device, in any order. Walked
    ///   once against a set of slugs rather than searched per record, so the
    ///   cost is the history's length rather than its length times the
    ///   catalogue's.
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

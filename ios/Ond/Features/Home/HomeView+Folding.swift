import OndKit
import SwiftUI

/// What Home is folded from, kept apart from how it is drawn.
///
/// The screen's two halves change for different reasons and at different times:
/// the layout moves when somebody redesigns a section, and this moves when a
/// rule about the catalogue, the history or the stars does. Splitting them also
/// puts every trigger's target in one place, which is where the question "does
/// anything re-fold when *this* changes" can actually be answered.
extension HomeView {
    /// The catalogue, or nothing until it lands.
    var loaded: [Technique] {
        guard case let .loaded(techniques) = catalogue.state else { return [] }
        return techniques
    }

    /// Everything breathable, keyed by slug and by what it is for.
    ///
    /// The catalogue *and* this person's own, which the chart's fold needs and
    /// went without: somebody practising only an exercise they wrote had days on
    /// the tiles and a chart that never appeared, because every one of their
    /// sessions was dropped for having no goal.
    private var goals: [String: TechniqueGoal] {
        (loaded + own.techniques).reduce(into: [:]) { goals, technique in
            goals[technique.slug] = technique.goal
        }
    }

    /// Re-folds what to offer.
    ///
    /// Split from the chart's fold because their inputs are different and so is
    /// their cost: a star tap changes what is on the shelf and nothing about the
    /// last four weeks, and re-bucketing a lifetime of history to answer one is
    /// work nobody asked for.
    ///
    /// Silent until the catalogue has landed. Every offer resolves a slug
    /// against it, so folding early produces an empty shelf that the next call
    /// replaces a beat later — and the triggers above include the load itself,
    /// so nothing waits.
    func foldShelf() {
        let techniques = loaded
        guard !techniques.isEmpty else { return }

        shelf = HomeShelf(
            techniques: techniques,
            routes: routes.available,
            history: journey.history,
            starred: stars.starred,
            hour: Calendar.current.component(.hour, from: .now),
            dialled: settings.overrides(forSlugsOf: techniques + own.techniques),
            authored: own.techniques
        )
    }

    /// Re-buckets the four weeks behind the chart.
    func foldRhythm() {
        guard !loaded.isEmpty else { return }

        rhythm = PracticeRhythm(sessions: journey.history, goals: goals)
    }
}

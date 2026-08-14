import OndKit
import SwiftUI

/// What Home offers, kept apart from how it is drawn.
///
/// The layout moves when somebody redesigns a section, while the shelf moves
/// when a rule about the catalogue, the history or the stars does. Splitting
/// them puts every trigger's target in one place, which is where the question
/// "does anything re-fold when *this* changes" can actually be answered.
extension HomeView {
    /// The catalogue, or nothing until it lands.
    var loaded: [Technique] {
        guard case let .loaded(techniques) = catalogue.state else { return [] }
        return techniques
    }

    /// Re-folds what to offer.
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
}

import Foundation
import Observation

/// What Home's button starts by default: one exercise, and the length to
/// breathe it for.
///
/// The sheet under Home's line is the only place this changes — not the last
/// session, not the hour, not a star. The line names the pace the button
/// starts with, and a default that quietly followed whatever was breathed last
/// would make the line a guess rather than a statement.
///
/// Minutes rather than a dialled technique, because the fit happens at draw
/// time against the person's current dials (`Technique.overrides(fitting:over:)`)
/// and nothing here must outlive a retuned exercise: a stored cycle count would
/// go on describing a length that dialling the phases had since changed.
public struct HomeChoice: Codable, Hashable, Sendable {
    /// The chosen exercise's slug — catalogue or authored.
    public var slug: String
    /// The asked-for length in whole minutes; one of `HomeOffer.lengths`.
    public var minutes: Int

    public init(slug: String, minutes: Int) {
        self.slug = slug
        self.minutes = minutes
    }
}

/// Where `HomeChoice` lives between launches.
///
/// `UserDefaults` on `StarredStopStore`'s terms: it belongs to the install, it
/// is a few bytes read at launch and written on a tap, and a deletion has to be
/// able to empty it — which is why it is composed in `OndApp` beside the other
/// personal stores rather than inside Home.
///
/// Nil until somebody chooses. `HomeOffer` answers the default from the
/// onboarding goal in that case, so Home never asks a question it could answer.
@MainActor
@Observable
public final class HomeChoiceStore: PersonalStore {
    /// The choice, or nil where none has been made.
    public private(set) var choice: HomeChoice?

    private let store: DefaultsJSONStore<HomeChoice>

    public init(defaults: UserDefaults = .standard) {
        store = DefaultsJSONStore(
            key: "home.choice",
            what: "the home choice",
            category: "home",
            defaults: defaults
        )
        choice = store.load()
    }

    /// Makes `slug` the default, keeping the chosen length — or the default
    /// length where nothing was chosen yet.
    public func choose(slug: String) {
        write(HomeChoice(slug: slug, minutes: choice?.minutes ?? HomeOffer.defaultMinutes))
    }

    /// Makes `minutes` the default length for `slug` — the exercise the sheet
    /// is showing as chosen, so that changing the length can never leave the
    /// store naming an exercise the person did not pick.
    public func choose(minutes: Int, for slug: String) {
        write(HomeChoice(slug: slug, minutes: minutes))
    }

    private func write(_ choice: HomeChoice) {
        guard choice != self.choice else { return }
        self.choice = choice
        store.save(choice)
    }

    /// Forgets the choice. What somebody decided to breathe by default is as
    /// personal as what they breathed.
    public func erase() async {
        choice = nil
        store.erase()
    }
}

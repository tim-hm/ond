import Foundation
import Observation

/// What Home's button starts by default: one exercise, and the length to
/// breathe it for. The sheet under Home's line is the only place this
/// changes — a default that quietly followed whatever was breathed last would
/// make the line a guess rather than a statement. Minutes, not a dialled
/// technique: a stored cycle count would outlive a retuned exercise.
public struct HomeChoice: Codable, Hashable, Sendable {
    /// The chosen exercise's slug — catalogue or authored.
    public var slug: TechniqueSlug
    /// The asked-for length in whole minutes; one of `HomeOffer.lengths`.
    public var minutes: Int

    public init(slug: TechniqueSlug, minutes: Int) {
        self.slug = slug
        self.minutes = minutes
    }
}

/// Where `HomeChoice` lives between launches — `UserDefaults` on
/// `StarredStopStore`'s terms, composed in `OndApp` beside the other personal
/// stores so a deletion can empty it. Nil until somebody chooses; `HomeOffer`
/// answers the default from the onboarding goal in that case.
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
    public func choose(slug: TechniqueSlug) {
        write(HomeChoice(slug: slug, minutes: choice?.minutes ?? HomeOffer.defaultMinutes))
    }

    /// Makes `minutes` the default length for `slug` — the exercise the sheet
    /// is showing as chosen, so that changing the length can never leave the
    /// store naming an exercise the person did not pick.
    public func choose(minutes: Int, for slug: TechniqueSlug) {
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

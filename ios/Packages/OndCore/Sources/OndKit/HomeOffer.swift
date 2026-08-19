import Foundation

/// What Home offers to breathe: one default exercise at one length, and the
/// two beside it in the sheet.
///
/// Three rows and no more, because Home is a button and the sheet under it is
/// the correction to the button, not a list. Exercises only — a protocol is a
/// moment's prescription and the Protocols tab is where moments live; Home
/// knows nothing of the hour, the last run, or the occasions. The default is
/// what the person chose in the sheet, and before they ever have, what the
/// onboarding goal implies — so Home never opens on a picker and never opens
/// empty.
///
/// Pure, over the catalogue and the stores that feed it, so every rule is a
/// claim under test rather than a layout's habit.
public struct HomeOffer: Sendable, Hashable {
    /// How many rows the sheet holds.
    public static let capacity = 3

    /// The lengths the sheet offers, in minutes — the seeded protocols' own
    /// vocabulary, and the three a person reaches for.
    public static let lengths = [3, 5, 10]

    /// The length before anyone has chosen one.
    public static let defaultMinutes = 5

    /// The slug Home falls back to with no choice and no goal: the pace the
    /// resting orb breathes at, so on a fresh install the line and the orb
    /// describe one breath.
    static let restingSlug = "coherent-breathing"

    /// The sheet's rows, the default first. Each stands at the person's own
    /// dials — the rhythm under its name is the rhythm it would play.
    public let rows: [DialStop]

    /// What the button starts: the first row, fitted to ``minutes`` — or
    /// playing its curated length where it cannot be fitted, which is why the
    /// line prints `lead.duration` and never `minutes`.
    public let lead: DialStop

    /// The asked-for length in whole minutes.
    public let minutes: Int

    /// Whether `lead` can be asked to last ``minutes`` at all. False for a
    /// staged or open-ended exercise, whose length is its shape; the sheet
    /// hides the Length row rather than offer three numbers that change
    /// nothing. Even when true, the length played is `lead.duration` — the
    /// cycle cap can fall short of ten minutes of a two-second breath.
    public var isFittable: Bool {
        lead.technique.isCyclic
    }

    /// Nil only when there is nothing to breathe, which is an empty catalogue.
    ///
    /// - Parameters:
    ///   - techniques: the catalogue, in its own order.
    ///   - authored: the exercises this person composed. Its own parameter
    ///     rather than merged into `techniques`, because the band a stop lands
    ///     in is which list it arrived in.
    ///   - starred ids: `StarredStopStore`'s whole set. Occasion stars are
    ///     ignored; an exercise star under any band counts.
    ///   - goals: the onboarding goals in the order they were picked.
    ///   - history: every session recorded on this device — read only to pick,
    ///     per goal, the exercise this person last breathed towards it.
    ///   - choice: what the sheet chose, if anything.
    ///   - dialled: what this person dialled themselves, keyed by slug.
    public init?(
        techniques: [Technique],
        authored: [Technique] = [],
        starred ids: Set<DialStop.ID> = [],
        goals: [TechniqueGoal] = [],
        history: [SessionRecord] = [],
        choice: HomeChoice?,
        dialled: [String: TechniqueOverrides] = [:]
    ) {
        guard !techniques.isEmpty else { return nil }

        let bySlug = DialStop.indexed(techniques)
            .merging(DialStop.indexed(authored)) { catalogue, _ in
                catalogue
            }

        var chosen: [Technique] = []
        var seen: Set<String> = []
        func admit(_ technique: Technique?) {
            guard chosen.count < Self.capacity, let technique, seen.insert(technique.slug).inserted
            else { return }
            chosen.append(technique)
        }

        // The default: the sheet's choice where it still resolves, the first
        // goal's exercise otherwise, and the resting pace with no goal at all.
        let implied = goals.first.map { goal in
            HomeSuggestion.technique(for: goal, techniques: techniques, history: history)
        }
        admit(choice.flatMap { bySlug[$0.slug] } ?? implied ?? bySlug[Self.restingSlug])

        // The stars, in dial order — this person's own, then the catalogue —
        // matched by every id that stands for an exercise, so a retained
        // `startHere/…` star still counts. Occasion ids match nothing here.
        let starred = (authored + techniques).filter { technique in
            !ids.isDisjoint(with: DialStop.ids(standingFor: technique))
        }
        for technique in starred {
            admit(technique)
        }

        // The remaining goals, one exercise each, in the order they were picked.
        for goal in goals.dropFirst() {
            admit(HomeSuggestion.technique(for: goal, techniques: techniques, history: history))
        }

        // The catalogue behind all of it, the resting pace first.
        admit(bySlug[Self.restingSlug])
        for technique in techniques {
            admit(technique)
        }

        rows = chosen.map { DialStop.standingFor($0, dialled: dialled[$0.slug]) }

        let minutes = choice?.minutes ?? Self.defaultMinutes
        let first = chosen[0]
        lead = DialStop.standingFor(
            first,
            dialled: first.overrides(fitting: .seconds(minutes * 60), over: dialled[first.slug])
        )
        self.minutes = minutes
    }
}

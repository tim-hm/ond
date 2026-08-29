import Foundation

/// What Home offers to breathe: one default exercise at one length, and the
/// two beside it in the sheet. Three rows and no more — the sheet is the
/// correction to the button, not a list. Exercises only; Home knows nothing
/// of the hour, the last run, or the occasions. Pure over the catalogue and
/// stores, so every rule is a claim under test rather than a layout's habit.
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
    /// describe one breath. `RestingBreathTests` holds that promise —
    /// `AmbientBreath.restingCycle` cannot name this exercise from OndUI,
    /// which knows nothing of a catalogue, so a test pins the pair instead.
    public static let restingSlug: TechniqueSlug = "coherent-breathing"

    /// The sheet's rows. Choosing a row the sheet already offers moves none of
    /// them; only a choice from outside takes a place, and it takes the last.
    /// Each stands at the person's own dials — the rhythm under its name is the
    /// rhythm it would play.
    public let rows: [DialStop]

    /// What the button starts: the chosen row, fitted to ``minutes`` — or
    /// playing its curated length where it cannot be fitted, which is why the
    /// line prints `lead.duration` and never `minutes`.
    public let lead: DialStop

    /// The asked-for length in whole minutes.
    public let minutes: Int

    /// Whether this row is the one the button starts. `lead` is always one of
    /// ``rows``, so exactly one row answers true.
    public func isChosen(_ stop: DialStop) -> Bool {
        stop.id == lead.id
    }

    /// Whether `lead` can be asked to last ``minutes`` at all. False for a
    /// staged or open-ended exercise, whose length is its shape; the sheet
    /// hides the Length row rather than offer three numbers that change
    /// nothing. Even when true, the length played is `lead.duration` — the
    /// cycle cap can fall short of ten minutes of a two-second breath.
    public var isFittable: Bool {
        lead.technique.isCyclic
    }

    /// Nil only when there is nothing to breathe: an empty catalogue.
    /// `authored` is its own parameter because the band a stop lands in is
    /// which list it arrived in. Each goal implies the catalogue's first
    /// exercise for it — never the one last breathed, or the line becomes a
    /// guess. A `choice` length outside ``lengths`` is treated as none.
    public init?(
        techniques: [Technique],
        authored: [Technique] = [],
        starred ids: Set<DialStop.ID> = [],
        goals: [TechniqueGoal] = [],
        choice: HomeChoice?,
        dialled: [TechniqueSlug: TechniqueOverrides] = [:]
    ) {
        guard !techniques.isEmpty else { return nil }

        let bySlug = DialStop.indexed(techniques)
            .merging(DialStop.indexed(authored)) { catalogue, _ in
                catalogue
            }

        var chosen: [Technique] = []
        func admit(_ technique: Technique?) {
            guard chosen.count < Self.capacity, let technique,
                  !chosen.contains(where: { $0.slug == technique.slug })
            else { return }
            chosen.append(technique)
        }

        // The default with nothing chosen: the first goal's exercise, and the
        // resting pace with no goal at all.
        let implied = goals.first.flatMap { goal in
            HomeSuggestion.technique(for: goal, techniques: techniques, history: [])
        }
        admit(implied ?? bySlug[Self.restingSlug])

        // The stars, in dial order — this person's own, then the catalogue —
        // matched by every id that stands for an exercise, so a retained
        // `startHere/…` star still counts. Occasion ids match nothing here.
        for technique in authored + techniques where DialStop.isStarred(technique, among: ids) {
            admit(technique)
        }

        // The remaining goals, one exercise each, in the order they were picked
        // — and no history scan for a goal the full sheet has no room for.
        for goal in goals.dropFirst() where chosen.count < Self.capacity {
            admit(HomeSuggestion.technique(for: goal, techniques: techniques, history: []))
        }

        // The catalogue behind all of it, the resting pace first.
        admit(bySlug[Self.restingSlug])
        for technique in techniques {
            admit(technique)
        }

        // The choice is always a row, and choosing never rearranges the sheet:
        // a choice the rows already offer stays where it is, and one from
        // outside takes the last place rather than the first.
        let picked = choice.flatMap { bySlug[$0.slug] }
        if let picked, !chosen.contains(where: { $0.slug == picked.slug }) {
            chosen = Array(chosen.prefix(Self.capacity - 1)) + [picked]
        }

        rows = chosen.map { DialStop.standingFor($0, dialled: dialled[$0.slug]) }

        let asked = choice?.minutes
        let minutes = asked.flatMap { Self.lengths.contains($0) ? $0 : nil } ?? Self.defaultMinutes
        let starts = picked ?? chosen[0]
        lead = DialStop.standingFor(
            starts,
            dialled: starts.overrides(fitting: .seconds(minutes * 60), over: dialled[starts.slug])
        )
        self.minutes = minutes
    }
}

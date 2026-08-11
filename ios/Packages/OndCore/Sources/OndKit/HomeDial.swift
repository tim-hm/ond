import Foundation

/// Home as a dial: one recommended thing in focus, and everything else a tick
/// away.
///
/// A flat list of stops rather than a tree, because one-in-focus has no room
/// for a hierarchy — you cannot expand what you cannot see beside itself. The
/// structure survives as `DialBand`, and what a surface does with it is the
/// surface's to decide.
///
/// The lead is a position, not a kind: whatever the routing layer chose keeps
/// its own band and its own words, and is simply first.
///
/// Pure, and given the hour rather than reading a clock, so every rule here is
/// testable at any time of day — the same reason `HomeSuggestion` takes one.
public struct HomeDial: Sendable, Hashable {
    /// Every stop, in tick order. Empty exactly when the catalogue is.
    public let stops: [DialStop]

    /// What sits in focus on arrival: the one thing the routing layer chose.
    /// Nil only when there is nothing to breathe at all.
    public var lead: DialStop? {
        stops.first
    }

    /// What a surface shows when it leaves the catalogue to the Exercises tab it
    /// already has — the named moments, the rungs of Start here, and whatever
    /// this person wrote, lead first — plus the catalogue entries they starred
    /// from an exercise's own screen.
    ///
    /// `yours` is in rather than out because it is the one band the Exercises tab
    /// cannot make redundant by being two icons away — an exercise somebody wrote
    /// is the one they are likeliest to want again, and leaving it out made home
    /// the only screen in the app that pretended it did not exist.
    ///
    /// A star is the one way a stop from `everything` earns a place. The band is
    /// filtered out because a board repeating it would be the Exercises tab with
    /// rounded corners; a star is somebody saying "this one, on my home screen",
    /// which is the one instruction that argument does not answer.
    ///
    /// Three rules beyond the filter, and all three are about the dial never
    /// pointing at something it does not draw.
    ///
    /// The fallback is decided before the stars fold in. A device that has never
    /// reached the server holds a catalogue and no routes at all, and this answers
    /// that with every stop rather than with an empty dial, which would be the one
    /// state where the app cannot be breathed. Deciding emptiness on the starred
    /// set instead would mean one star turned that whole-catalogue fallback into a
    /// home screen with a single card on it — a star taking away every exercise
    /// but the one it named.
    ///
    /// The lead keeps its place whichever band it came from, and appears once.
    /// `lead(…)`'s last fallback is a catalogue entry, which the filter would
    /// otherwise drop — and that fallback is the ordinary case for most of a
    /// working day, because no seeded occasion borrows the `energy` or `focus`
    /// goals the morning and afternoon route to. Dropping it leaves the dial
    /// focused on a stop no row draws. It may also be starred, which is likely the
    /// moment somebody stars what home just offered them, and prepending it again
    /// would put one stop in the list twice.
    ///
    /// And a starred stop keeps dial order rather than star order, which is why
    /// `StarredStopStore` holds a set: `everything` is the last band, so a starred
    /// catalogue entry sits behind the moments, the rungs and this person's own,
    /// and moving it to the front of the deck is `HomeDeck`'s decision from there.
    ///
    /// - Parameter starred: the ids this person starred — `StarredStopStore`'s
    ///   whole set. Ids from the other three bands cost nothing to pass: they are
    ///   already here, or they name a stop the routes no longer send and are inert.
    public func routed(starring starred: Set<DialStop.ID> = []) -> [DialStop] {
        guard stops.contains(where: { $0.band != .everything }) else { return stops }

        let routed = stops.filter { $0.band != .everything || starred.contains($0.id) }

        guard let lead, lead.band == .everything else { return routed }

        return [lead] + routed.filter { $0.id != lead.id }
    }

    /// - Parameters:
    ///   - techniques: the catalogue, in its own order — the `everything` band
    ///     is this list and the two other bands resolve into it.
    ///   - routes: the occasions and the progression. `.none` is a supported
    ///     state, not a degraded one to guard against: a device that has never
    ///     reached the server has a catalogue and no routes, and the dial is
    ///     then the catalogue with the hour's suggestion in front.
    ///   - history: every session recorded on this device, in any order. Read
    ///     for two things — whether this person has ever breathed anything, and
    ///     which rung of Start here they have reached.
    ///   - hour: the local hour, 0–23, which picks the occasion somebody with
    ///     history is most likely to have opened the app for.
    ///   - dialled: what this person has dialled themselves, keyed by slug.
    ///     Passed in rather than reached for, so this stays pure — and passed at
    ///     all because a stop states a length, which the session it starts then
    ///     has to keep.
    ///   - authored: the exercises this person composed. Its own parameter rather
    ///     than merged into `techniques` by the caller, because the two arrive
    ///     from different services on different loads and only one of them needs
    ///     an identity — a home screen that waited to have both before drawing
    ///     anything would wait on the slower of them every launch. Defaulted, so
    ///     a caller with no authoring surface says nothing.
    public init(
        techniques: [Technique],
        routes: Routes,
        history: [SessionRecord],
        hour: Int,
        dialled: [String: TechniqueOverrides] = [:],
        authored: [Technique] = []
    ) {
        // First slug wins, which the catalogue's own uniqueness makes moot —
        // stated only because `Dictionary(uniqueKeysWithValues:)` would trap on
        // a duplicate the server is free to send.
        let bySlug = Dictionary(techniques.map { ($0.slug, $0) }) { first, _ in first }

        let occasions = routes.occasions.compactMap { occasion in
            bySlug[occasion.prescription.techniqueSlug].map { technique in
                DialStop(
                    technique: technique,
                    origin: .occasion(occasion),
                    band: .occasions,
                    saved: dialled[technique.slug]
                )
            }
        }

        let steps = routes.progression.compactMap { step in
            bySlug[step.techniqueSlug].map { technique in
                DialStop(
                    technique: technique,
                    origin: .step(step),
                    band: .startHere,
                    saved: dialled[technique.slug]
                )
            }
        }

        let yours = authored.map { technique in
            DialStop(
                technique: technique,
                origin: .technique,
                band: .yours,
                saved: dialled[technique.slug]
            )
        }

        let everything = techniques.map { technique in
            DialStop(
                technique: technique,
                origin: .technique,
                band: .everything,
                saved: dialled[technique.slug]
            )
        }

        // Authored exercises are deliberately not candidates. The lead is what
        // the routing layer chose, and nothing routes to one somebody wrote: the
        // occasions name catalogue slugs, the progression is curated, and the
        // hour's suggestion reads goals the catalogue publishes. Home leading on
        // an authored exercise would be the app recommending back what it was
        // handed.
        let chosen = Self.lead(
            occasions: occasions,
            steps: steps,
            everything: everything,
            history: history,
            hour: hour
        )

        // Deduplicated once over the assembled list rather than three times over
        // the parts, for the reason `bySlug` coalesces: a slug the server sent
        // twice would be two stops sharing one id, and a duplicate identity is a
        // row the dial can neither scroll to nor step onto. Stated here, the
        // three bands do not each have to remember it.
        var seen: Set<String> = []
        stops = Self.ordered(leadingWith: chosen, among: [occasions, steps, yours, everything])
            .filter { seen.insert($0.id).inserted }
    }

    /// The stops in tick order: the lead first, then the rest of its own band,
    /// then the other bands in their own order.
    ///
    /// The lead's band is promoted with it, rather than the lead alone being
    /// lifted to the front of a fixed band order. Lifting it alone reads fine
    /// when the lead is the first band's — and splits a band in half when it is
    /// not. The common case is exactly that: a person on their first run leads
    /// with the first rung of Start here, and the rest of the course would then
    /// sit below every unrelated occasion, so the one screen that promised a
    /// single kind of thing at a time would open on a course cut in two.
    ///
    /// - Parameters:
    ///   - lead: the stop to open on, or nil where there is nothing to breathe.
    ///   - bands: the stops grouped by band, in `DialBand`'s own order.
    private static func ordered(
        leadingWith lead: DialStop?,
        among bands: [[DialStop]]
    ) -> [DialStop] {
        guard let lead else { return bands.flatMap(\.self) }

        let own = bands.filter { $0.contains { $0.id == lead.id } }.flatMap(\.self)
        let others = bands.filter { !$0.contains { $0.id == lead.id } }.flatMap(\.self)

        return [lead] + own.filter { $0.id != lead.id } + others
    }

    /// The one thing home leads with, in the order the routing model ratified.
    ///
    /// A person who has breathed nothing meets Start here, which is what the
    /// progression is for. Everybody else meets the occasion that fits the hour
    /// — the clock is already how this app guesses at a life event, and an
    /// occasion is that guess made explicit rather than inferred into a goal.
    /// The two fallbacks behind it are what keep the dial answering on a device
    /// with no routes at all.
    private static func lead(
        occasions: [DialStop],
        steps: [DialStop],
        everything: [DialStop],
        history: [SessionRecord],
        hour: Int
    ) -> DialStop? {
        let goal = HomeSuggestion.goal(forHour: hour)

        if history.isEmpty, let first = steps.first {
            return first
        }

        if let fitting = occasions.first(where: { $0.goal == goal }) {
            return fitting
        }

        // The rung this person has reached: the first whose exercise they have
        // never breathed. Read from the resolved stops rather than from the
        // progression itself, so a step naming an exercise the catalogue no
        // longer holds is skipped rather than leading to nothing.
        let breathed = Set(history.map(\.techniqueSlug))
        if let reached = steps.first(where: { !breathed.contains($0.technique.slug) }) {
            return reached
        }

        let suggested = HomeSuggestion.technique(
            for: goal,
            techniques: everything.map(\.technique),
            history: history
        )
        return everything.first { $0.technique.slug == suggested?.slug }
    }
}

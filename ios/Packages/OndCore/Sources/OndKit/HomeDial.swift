import Foundation

/// The three kinds of thing the dial holds, in the order it ticks through them.
///
/// Three kinds and no more, because a band is a promise about what a stop *is*
/// — a named moment, a rung of a course, an exercise standing for itself — and
/// the recommendation is none of those. It is one of them, moved to the front.
/// A fourth band for it put four kinds of thing in one scroll and left the
/// reader holding all four; the lead is a position now, not a zone.
///
/// What a surface does with the bands is its own decision. The phone's home
/// shows only the two that are routes and leaves `everything` to the Exercises
/// tab, which is what `routed` is for.
public enum DialBand: String, Sendable, Hashable, CaseIterable {
    /// The named moments — `Routes.occasions`, in seeded order.
    case occasions

    /// The curated ordering for somebody who has picked no goal at all.
    case startHere

    /// The whole catalogue, so nothing the app has is unreachable from home.
    case everything
}

/// One thing the dial can come to rest on.
///
/// Every stop resolves to a technique, whichever band it came from: a route
/// nobody can breathe is not a stop, and keeping the technique on the value is
/// what lets the orb underneath the dial be the same control for all three
/// bands.
public struct DialStop: Sendable, Hashable, Identifiable {
    /// What this stop was before the dial flattened it, which is what decides
    /// the words shown and the promise made.
    public enum Origin: Sendable, Hashable {
        /// A named moment, with the goal, surface and dose it prescribes.
        case occasion(Occasion)
        /// A rung of Start here. Its position is the dial's own — the band it
        /// sits in is already in curated order.
        case step(ProgressionStep)
        /// A catalogue entry, standing for itself.
        case technique
    }

    public let technique: Technique
    public let origin: Origin
    public let band: DialBand

    /// The dials this stop starts with, or nil where the technique is played
    /// exactly as the catalogue curated it.
    public let dose: TechniqueOverrides?

    /// How long this stop actually takes — read off the dialled technique
    /// rather than off the prescription, because an occasion asking for five
    /// minutes of something four minutes long gets four.
    public let duration: Duration

    /// Stored rather than computed, both of them, because the dial's rows are
    /// drawn on every layout pass and `dialled(with:)` rebuilds a whole
    /// technique to answer. A stop is built once per rebuild; this is the work
    /// that belongs there.
    ///
    /// - Parameter saved: what this person dialled for `technique` themselves,
    ///   or nil where they took it as curated. An occasion overrules it — that
    ///   is what the word prescription means, and "a minute to come down from a
    ///   spike" is an offer about a length. Everywhere else it wins, and it has
    ///   to reach here rather than only the Begin: the row states a length, and
    ///   a length stated is a length the orb owes.
    init(technique: Technique, origin: Origin, band: DialBand, saved: TechniqueOverrides?) {
        self.technique = technique
        self.origin = origin
        self.band = band

        dose = switch origin {
        case let .occasion(occasion): occasion.prescription.dose(for: technique)
        case .step, .technique: saved
        }
        duration = technique.dialled(with: dose).plannedDuration
    }

    /// Unique across the whole dial, which the technique's slug is not: Start
    /// here names four of the catalogue's nine, so the same exercise is a stop
    /// in two bands and the scroll position needs to tell them apart.
    public var id: String {
        "\(band.rawValue)/\(key)"
    }

    /// The stop's name in its own band, before the band is prefixed.
    private var key: String {
        switch origin {
        case let .occasion(occasion): occasion.slug
        case .step, .technique: technique.slug
        }
    }

    /// The line in focus.
    public var title: String {
        switch origin {
        case let .occasion(occasion): occasion.name
        case .step, .technique: technique.name
        }
    }

    /// The sentence under it. A step's note is why this one at this point,
    /// which is the whole of what makes the order a progression — and where a
    /// step has none, the technique's own summary is contracted to be enough.
    public var detail: String {
        switch origin {
        case let .occasion(occasion):
            occasion.summary.isEmpty ? technique.summary : occasion.summary
        case let .step(step):
            step.note.isEmpty ? technique.summary : step.note
        case .technique:
            technique.summary
        }
    }

    /// The goal this stop is framed as, and therefore the accent it wears. An
    /// occasion borrows one rather than reading the technique's, because what a
    /// moment is for must not move because a technique was re-grouped.
    public var goal: TechniqueGoal {
        switch origin {
        case let .occasion(occasion): occasion.prescription.goal
        case .step, .technique: technique.goal
        }
    }

    /// How loudly this stop runs. Everything outside an occasion is full
    /// screen: the catalogue makes no promise about quietness, and inventing
    /// one here would be this app guessing at a route the server never sent.
    public var surface: DeliverySurface {
        switch origin {
        case let .occasion(occasion): occasion.prescription.surface
        case .step, .technique: .fullScreen
        }
    }
}

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
    /// already has: the named moments and the rungs of Start here, lead first.
    ///
    /// Two rules beyond the filter, and both are about the dial never pointing
    /// at something it does not draw.
    ///
    /// It falls back to every stop rather than to nothing. A device that has
    /// never reached the server holds a catalogue and no routes at all, and a
    /// home screen answering that with an empty dial would be the one state
    /// where this app cannot be breathed.
    ///
    /// And it keeps the lead whichever band it came from. `lead(…)`'s last
    /// fallback is a catalogue entry, which the filter would otherwise drop —
    /// and that fallback is the ordinary case for most of a working day, because
    /// no seeded occasion borrows the `energy` or `focus` goals the morning and
    /// afternoon route to. Dropping it leaves the dial focused on a stop no row
    /// draws: nothing bold, nothing tinted, no sentence, and a Begin button that
    /// starts an exercise the screen never named.
    public var routed: [DialStop] {
        let routed = stops.filter { $0.band != .everything }

        guard !routed.isEmpty else { return stops }
        guard let lead, lead.band == .everything else { return routed }

        return [lead] + routed
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
    public init(
        techniques: [Technique],
        routes: Routes,
        history: [SessionRecord],
        hour: Int,
        dialled: [String: TechniqueOverrides] = [:]
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

        let everything = techniques.map { technique in
            DialStop(
                technique: technique,
                origin: .technique,
                band: .everything,
                saved: dialled[technique.slug]
            )
        }

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
        stops = Self.ordered(leadingWith: chosen, among: [occasions, steps, everything])
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
    /// sit below five unrelated occasions, so the one screen that promised a
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

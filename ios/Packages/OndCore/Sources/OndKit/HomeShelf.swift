import Foundation

/// Everything Home offers to breathe, in the order it offers it: what the hour
/// suggests, what was breathed last, and what this person starred.
///
/// The three rules that survived the dial. The old screen expressed them as one
/// long list with a lead at the front and a deck deciding the rest; Home now
/// folds them into one continue card, then keeps the shelf below.
/// The rules live here rather than in the view because every one of them is a
/// claim about somebody's history.
///
/// The suggestion and the rerun are the lead's two constituents, and only one
/// of them shows: ``lead`` takes the last run where it still resolves and the
/// hour's suggestion otherwise. Starred excludes only what the card actually
/// took — the constituent it passed over is not on screen and must not vanish
/// from the shelf with it.
///
/// A starred stop taken by the card keeps its star affordance, because the
/// card's stop can be starred anywhere else it appears — losing the row is not
/// losing the control.
///
/// Pure, and given the hour rather than reading a clock, so every rule here is
/// testable at any time of day — the same reason `HomeSuggestion` takes one.
public struct HomeShelf: Sendable, Hashable {
    /// The most recent session, resolved back to something that can be started
    /// again.
    public struct LastRun: Sendable, Hashable {
        public let stop: DialStop
        /// When the session began.
        public let at: Date
    }

    /// What the continue card holds: one stop, and which of the two rules put
    /// it there — the eyebrow's one fact, so the card never passes a rerun off
    /// as a fresh idea or the reverse.
    public struct Lead: Sendable, Hashable {
        public let stop: DialStop
        /// Whether starting `stop` repeats the last run rather than taking the
        /// hour's suggestion.
        public let resumes: Bool

        /// The word the card states over the title — the flag as the person
        /// reads it, pinned here so an inverted mapping cannot quietly pass a
        /// rerun off as a fresh idea.
        public var eyebrow: String {
            resumes ? "Continue" : "Suggested now"
        }
    }

    /// Everything breathable, resolved once.
    ///
    /// One value rather than five parameters repeated down the folds below.
    /// Every rule here starts from the same join — the occasions against the
    /// catalogue, plus whatever this person wrote and whatever they dialled —
    /// and passing the parts separately let one fold be handed a catalogue and
    /// another an authored list assembled from it.
    private struct Resolved {
        let occasions: [DialStop]
        let steps: [DialStop]
        let techniques: [Technique]
        let bySlug: [String: Technique]
        let authored: [Technique]
        let dialled: [String: TechniqueOverrides]
    }

    /// What the hour offers — the lead's fallback, in the order the routing
    /// model ratified.
    ///
    /// A person who has breathed nothing meets Start here, which is what the
    /// progression is for. Everybody else meets the protocol that fits the hour
    /// — the clock is already how this app guesses at a life event, and a
    /// protocol is that guess made explicit rather than inferred into a goal.
    /// The two fallbacks behind it are what keep Home answering on a device with
    /// no occasions at all.
    ///
    /// Nil only when there is nothing to breathe, which is an empty catalogue.
    ///
    /// Internal: screens read ``lead``, which already chose between the two
    /// constituents — a second public road to one of them is how a future
    /// caller re-shows the stop the lead passed over. The tests reach it to
    /// pin the routing on its own.
    let suggested: DialStop?

    /// The last thing breathed, or nil where nothing has been or where what was
    /// breathed has since left the catalogue. Internal for ``suggested``'s
    /// reason.
    let lastRun: LastRun?

    /// The one offer Home leads with: the last run where it still resolves,
    /// the hour's suggestion otherwise, or nil while there is nothing to
    /// breathe. The rerun wins because somebody re-opening the app mid-practice
    /// is likelier carrying on than asking for a new idea — and because a
    /// suggestion is a guess where a rerun is a record.
    public let lead: Lead?

    /// The starred stops, in dial order — protocols, then rungs, then this
    /// person's own, then the catalogue — less anything already shown above.
    ///
    /// Dial order rather than star order, which is why `StarredStopStore` holds
    /// a set: two stars stay in the order Home would have shown them anyway, and
    /// starring cannot quietly become a second sort nobody asked for.
    ///
    /// An id naming a stop the occasions no longer send resolves to nothing and is
    /// silently dropped. That is the whole of the answer for the `startHere/…`
    /// stars a rung's star affordance once wrote: the keyspace is unchanged, the
    /// key is simply inert.
    public let starred: [DialStop]

    /// - Parameters:
    ///   - techniques: the catalogue, in its own order.
    ///   - occasions: the protocols and the progression. `OccasionCatalogue.none` is a
    ///     supported state — a device that has never reached the server still
    ///     has a catalogue, and both the suggestion and a star against it still
    ///     resolve.
    ///   - history: every session recorded on this device, in any order.
    ///   - starred ids: the ids this person starred — `StarredStopStore`'s whole
    ///     set.
    ///   - hour: the local hour, 0–23, which picks the protocol somebody with
    ///     history is most likely to have opened the app for.
    ///   - dialled: what this person dialled themselves, keyed by slug, so a row
    ///     states the length the session it starts will actually play.
    ///   - authored: the exercises this person composed. Its own parameter
    ///     rather than merged into `techniques`, because the two arrive from
    ///     different services on different loads and only one of them needs an
    ///     identity — and because the band a stop lands in is which list it
    ///     arrived in.
    public init(
        techniques: [Technique],
        occasions: OccasionCatalogue,
        history: [SessionRecord],
        starred ids: Set<DialStop.ID>,
        hour: Int,
        dialled: [String: TechniqueOverrides] = [:],
        authored: [Technique] = []
    ) {
        let bySlug = DialStop.indexed(techniques)
        let resolved = Resolved(
            occasions: DialStop.occasions(of: occasions, resolvedBy: bySlug, dialled: dialled),
            steps: DialStop.steps(of: occasions, resolvedBy: bySlug, dialled: dialled),
            techniques: techniques,
            bySlug: bySlug,
            authored: authored,
            dialled: dialled
        )

        let suggested = Self.suggestion(in: resolved, history: history, hour: hour)
        let lastRun = Self.lastRun(in: history, among: resolved)

        self.suggested = suggested
        self.lastRun = lastRun

        let lead = lastRun.map { Lead(stop: $0.stop, resumes: true) }
            ?? suggested.map { Lead(stop: $0, resumes: false) }
        self.lead = lead

        // Only what the card took, not both candidates: the constituent it
        // passed over appears nowhere above the shelf, and excluding it would
        // make its star vanish from the screen entirely.
        var shown: Set<DialStop.ID> = []
        if let lead {
            shown.insert(lead.stop.id)
        }

        starred = Self.starred(ids: ids, among: resolved)
            .filter { shown.insert($0.id).inserted }
    }

    /// The starred stops, in `DialBand`'s own order.
    ///
    /// The catalogue and the authored list are filtered *before* a stop is built
    /// for them, which is the difference between allocating a stop per starred
    /// row and allocating one per exercise the app has ever shipped. It is safe
    /// because `DialStop.id(of:)` answers a technique's own id without a stop
    /// existing — that is what it is for, and
    /// `everyStandaloneStopCarriesTheIdItsTechniqueAnswersWith` is what holds
    /// the two answers together.
    private static func starred(ids: Set<DialStop.ID>, among resolved: Resolved) -> [DialStop] {
        func standing(_ list: [Technique]) -> [DialStop] {
            list.filter { ids.contains(DialStop.id(of: $0)) }
                .map { DialStop.standingFor($0, dialled: resolved.dialled[$0.slug]) }
        }

        return resolved.occasions.filter { ids.contains($0.id) }
            + resolved.steps.filter { ids.contains($0.id) }
            + standing(resolved.authored)
            + standing(resolved.techniques)
    }

    /// What Home leads with — see ``suggested``.
    private static func suggestion(
        in resolved: Resolved,
        history: [SessionRecord],
        hour: Int
    ) -> DialStop? {
        let goal = HomeSuggestion.goal(forHour: hour)

        if history.isEmpty, let first = resolved.steps.first {
            return first
        }

        if let fitting = resolved.occasions.first(where: { $0.goal == goal }) {
            return fitting
        }

        // The rung this person has reached: the first whose exercise they have
        // never breathed. Read from the resolved stops rather than from the
        // progression itself, so a step naming an exercise the catalogue no
        // longer holds is skipped rather than led to.
        let breathed = Set(history.map(\.techniqueSlug))
        if let reached = resolved.steps.first(where: { !breathed.contains($0.technique.slug) }) {
            return reached
        }

        return HomeSuggestion
            .technique(for: goal, techniques: resolved.techniques, history: history)
            .map { DialStop.standingFor($0, dialled: resolved.dialled[$0.slug]) }
    }

    /// The most recent session, resolved to the stop that would replay it.
    ///
    /// The protocol wins where the record carries one and it still resolves,
    /// which is what makes the row a rerun rather than an approximation: a
    /// session prescribed by "Before a presentation" was two minutes long and
    /// spoken in that moment's register, and offering the plain exercise instead
    /// would quietly hand back a different session under the same name.
    ///
    /// Nil where the exercise has left the catalogue. A row that could not be
    /// started is worse than no row, and the History screen is where a session
    /// outliving its exercise is still visible.
    private static func lastRun(
        in history: [SessionRecord],
        among resolved: Resolved
    ) -> LastRun? {
        guard let latest = history.max(by: { $0.startedAt < $1.startedAt }) else { return nil }

        if let slug = latest.occasionSlug {
            // Nested rather than a second condition on the `if`, so the
            // formatter's wrapping of a multi-clause binding and the linter's
            // brace rule stop disagreeing over this one line.
            if let stop = resolved.occasions.first(where: { $0.occasionSlug == slug }) {
                return LastRun(stop: stop, at: latest.startedAt)
            }
        }

        // The catalogue first, then this person's own. Only the order of a
        // collision is being decided and the two keyspaces do not overlap in
        // practice; stated so the answer is not whichever lookup was written
        // first.
        let authored = DialStop.indexed(resolved.authored)
        guard let technique = resolved.bySlug[latest.techniqueSlug]
            ?? authored[latest.techniqueSlug]
        else {
            return nil
        }

        return LastRun(
            stop: .standingFor(technique, dialled: resolved.dialled[technique.slug]),
            at: latest.startedAt
        )
    }
}

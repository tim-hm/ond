import Foundation

/// What Home has to offer that nothing else on the screen derives: the stops
/// this person starred, and the one they last ran.
///
/// Two folds rather than two types because they answer one question — what is
/// already yours — and both need the same join to answer it. Everything else
/// Home draws is somebody's own numbers (`JourneyStats`), the hour's guess
/// (`HomeSuggestion`), or a door.
///
/// Pure, and given the history rather than reading a store, on `JourneyStats`'
/// terms: an order that depends on what somebody has done has to be testable
/// without having done it. Unlike the dial it replaces, it reads no clock at
/// all — nothing here changes between two layout passes, which is what lets the
/// screen hold it as plain state and rebuild only when a star, an authored
/// exercise or a session actually moves.
public struct HomeShelf: Sendable, Hashable {
    /// The most recent session, resolved back to something that can be started
    /// again.
    public struct LastRun: Sendable, Hashable {
        public let stop: DialStop
        /// When it was, for the relative date the row prints.
        public let at: Date
    }

    /// The starred stops, in dial order — occasions, then rungs, then this
    /// person's own, then the catalogue.
    ///
    /// Dial order rather than star order, which is why `StarredStopStore` holds
    /// a set: two stars stay in the order Home would have shown them anyway, and
    /// starring cannot quietly become a second sort nobody asked for.
    ///
    /// An id naming a stop the routes no longer send resolves to nothing and is
    /// silently dropped. That is the whole of the answer for the `startHere/…`
    /// stars a rung's star affordance once wrote: the keyspace is unchanged, the
    /// key is simply inert.
    public let starred: [DialStop]

    /// The last thing breathed, or nil where nothing has been or where what was
    /// breathed has since left the catalogue.
    public let lastRun: LastRun?

    /// - Parameters:
    ///   - techniques: the catalogue, in its own order.
    ///   - routes: the occasions and the progression. `Routes.none` is a
    ///     supported state — a device that has never reached the server still
    ///     has a catalogue, and stars against it still resolve.
    ///   - history: every session recorded on this device, in any order.
    ///   - starred: the ids this person starred — `StarredStopStore`'s whole
    ///     set.
    ///   - dialled: what this person dialled themselves, keyed by slug, so a row
    ///     states the length the session it starts will actually play.
    ///   - authored: the exercises this person composed. Its own parameter
    ///     rather than merged into `techniques`, because the two arrive from
    ///     different services on different loads and only one of them needs an
    ///     identity — and because the band a stop lands in is which list it
    ///     arrived in.
    public init(
        techniques: [Technique],
        routes: Routes,
        history: [SessionRecord],
        starred ids: Set<DialStop.ID>,
        dialled: [String: TechniqueOverrides] = [:],
        authored: [Technique] = []
    ) {
        let bySlug = DialStop.indexed(techniques)

        // `DialBand`'s own order, which is the order a star is honoured in.
        let bands = [
            DialStop.occasions(of: routes, resolvedBy: bySlug, dialled: dialled),
            DialStop.steps(of: routes, resolvedBy: bySlug, dialled: dialled),
            DialStop.standalone(authored, in: .yours, dialled: dialled),
            DialStop.standalone(techniques, in: .everything, dialled: dialled),
        ]

        // Deduplicated over the assembled list rather than per band: a slug the
        // server sent twice would be two stops sharing one id, and a duplicate
        // identity is a row `ForEach` cannot tell apart.
        var seen: Set<DialStop.ID> = []
        let stops = bands.flatMap(\.self).filter { seen.insert($0.id).inserted }

        starred = stops.filter { ids.contains($0.id) }
        lastRun = Self.lastRun(in: history, among: stops)
    }

    /// The most recent session, resolved to the stop that would replay it.
    ///
    /// The occasion wins where the record carries one and it still resolves,
    /// which is what makes the row a rerun rather than an approximation: a
    /// session prescribed by "Before a presentation" was two minutes long and
    /// spoken in that moment's register, and offering the plain exercise instead
    /// would quietly hand back a different session under the same name.
    ///
    /// Nil where the exercise has left the catalogue. A row that could not be
    /// started is worse than no row, and the history strip on the History screen
    /// is where a session outliving its exercise is still visible.
    private static func lastRun(
        in history: [SessionRecord],
        among stops: [DialStop]
    ) -> LastRun? {
        guard let latest = history.max(by: { $0.startedAt < $1.startedAt }) else { return nil }

        let routed = latest.occasionSlug.flatMap { slug in
            stops.first { $0.occasionSlug == slug }
        }

        guard let stop = routed ?? stops.first(where: {
            $0.origin == .technique && $0.technique.slug == latest.techniqueSlug
        }) else {
            return nil
        }

        return LastRun(stop: stop, at: latest.startedAt)
    }
}

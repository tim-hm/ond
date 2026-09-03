import Foundation

/// What the watch offers on its front door: the exercises this person
/// actually breathes, most recent first, topped up from the catalogue in its
/// own curated order — a wrist that has never breathed anything must not
/// open empty, because this device works before it has seen the phone.
/// Pure, and tested, because every line is a claim about somebody's history.
public struct WristShelf: Sendable, Hashable {
    /// How many cards the front door holds. Three: a watch screen shows about
    /// that many at a glance, and a fourth is a scroll for something the
    /// carousel behind it already lists in full.
    public static let capacity = 3

    /// The stops to offer, most recently breathed first. Never longer than
    /// ``capacity``, and empty only when the catalogue itself is.
    public let stops: [DialStop]

    /// No dials parameter, unlike `HomeOffer`: the wrist has no screen that
    /// sets them, so a card states the exercise's own length. `tier` is applied
    /// by `unlocked(for:)` to both sources at once, so a locked exercise drops
    /// out of the history as well as the catalogue.
    public init(techniques: [Technique], history: [SessionRecord], tier: SubscriptionTier) {
        let offered = techniques.unlocked(for: tier)
        let bySlug = DialStop.indexed(offered)

        // Newest first, then the catalogue's own order behind it, then each
        // slug taken once and the rest cut. A session whose exercise has left
        // the catalogue resolves to nothing and drops out here rather than
        // becoming a card that could not be started.
        var seen: Set<TechniqueSlug> = []
        stops = (history.sorted { $0.startedAt > $1.startedAt }.map(\.techniqueSlug)
            + offered.map(\.slug))
            .filter { bySlug[$0] != nil && seen.insert($0).inserted }
            .prefix(Self.capacity)
            .compactMap { bySlug[$0] }
            .map { DialStop.standingFor($0) }
    }
}

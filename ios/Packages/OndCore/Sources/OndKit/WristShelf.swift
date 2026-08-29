import Foundation

/// What the watch offers on its front door: the exercises this person actually
/// breathes, most recent first, topped up from the catalogue.
///
/// The wrist's answer to the question Home's continue card answers in the hand,
/// and a deliberately simpler one. There are no stars on this device, no
/// occasions worth routing through three cards, and no hour-of-day guess — a
/// watch is reached for while already knowing what is wanted, and the fastest
/// screen is the one that puts last night's exercise under the thumb.
///
/// Topped up rather than left short: a wrist that has never breathed anything
/// would otherwise open empty, and the standalone promise is that this device
/// works before it has ever seen the phone. The fill comes from the catalogue in
/// its own curated order, which is the order the Exercises carousel turns in.
///
/// Pure, and tested, because every line of it is a claim about somebody's
/// history — the same reason `HomeOffer`'s rules are not in a view.
public struct WristShelf: Sendable, Hashable {
    /// How many cards the front door holds. Three: a watch screen shows about
    /// that many at a glance, and a fourth is a scroll for something the
    /// carousel behind it already lists in full.
    public static let capacity = 3

    /// The stops to offer, most recently breathed first. Never longer than
    /// ``capacity``, and empty only when the catalogue itself is.
    public let stops: [DialStop]

    /// - Parameters:
    ///   - techniques: the catalogue, in its own order.
    ///   - history: every session recorded on this device, in any order.
    ///
    /// No dials parameter, unlike `HomeOffer`: the wrist has no screen that
    /// sets them, so a card here states the exercise's own length and the
    /// session it starts plays exactly that. The day the watch can re-dial
    /// something is the day this takes them.
    public init(techniques: [Technique], history: [SessionRecord]) {
        let bySlug = DialStop.indexed(techniques)

        // Newest first, then the catalogue's own order behind it, then each
        // slug taken once and the rest cut. A session whose exercise has left
        // the catalogue resolves to nothing and drops out here rather than
        // becoming a card that could not be started.
        var seen: Set<String> = []
        stops = (history.sorted { $0.startedAt > $1.startedAt }.map(\.techniqueSlug)
            + techniques.map(\.slug))
            .filter { bySlug[$0] != nil && seen.insert($0).inserted }
            .prefix(Self.capacity)
            .compactMap { bySlug[$0] }
            .map { DialStop.standingFor($0) }
    }
}

import Foundation

/// A session order the wrist can actually run: the order, the technique it
/// resolved to, and the name to put above it.
///
/// Resolution is the wrist's one chance to decline. The order arrives as two
/// slugs, and a watch whose catalogue is older than the phone's may hold
/// neither — so this is where "the wrist said no" is decided, rather than three
/// screens later where the answer would be a blank face.
///
/// In `OndKit` rather than the watch target because the fallback below is a
/// judgement, not plumbing, and the watch target has no test bundle.
public struct OrderedMoment: Sendable, Identifiable {
    public let order: WatchSessionOrder
    public let technique: Technique
    /// What the screen calls this session. The occasion's own name where the
    /// wrist can see the route, and the technique's where it cannot.
    public let occasionName: String

    /// The order's id, so a `sheet(item:)` presenting this is keyed to the
    /// exchange rather than to whatever it resolved to.
    public var id: UUID {
        order.id
    }

    /// Resolves `order` against what this watch holds, or answers nil where the
    /// technique it names is not in the catalogue.
    ///
    /// The occasion is resolved on softer terms than the technique, deliberately.
    /// A missing technique means there is nothing to breathe; a missing occasion
    /// means only that this wrist's copy of the routes is behind its phone's,
    /// and the phone has already decided this session is worth running. So the
    /// name falls back to the technique's rather than the order being refused —
    /// a person in a meeting is better served by the right rhythm under the
    /// wrong heading than by nothing at all.
    public init?(
        order: WatchSessionOrder,
        techniques: [Technique],
        occasions: [Occasion]
    ) {
        guard let technique = techniques.first(where: { $0.slug == order.techniqueSlug }) else {
            return nil
        }

        self.order = order
        self.technique = technique
        occasionName = occasions
            .first { $0.slug == order.occasionSlug }?
            .name ?? technique.name
    }
}

import Foundation

/// Where a tapped notification opens, once its slug is matched against the
/// catalogue and the tier the person is on. Two answers and no third. A served
/// catalogue lets a slug outlive the technique it names, so a slug that
/// resolves to nothing returns nil from the initialiser and the app opens
/// where it would have opened anyway.
public enum NotificationDestination: Sendable, Equatable {
    /// The exercise's session screen, held at rest until the person begins it.
    /// Being reminded is not the same as being ready.
    case session(Technique)

    /// The subscription offer, opened on the tier this exercise needs.
    ///
    /// Not the session screen: one that cannot start is the one place a
    /// reminder must never land. The catalogue also sends a tap on a locked
    /// exercise here, so the two agree.
    case offer(Technique)

    /// Resolves `payload` against the catalogue, or nil where the slug names
    /// nothing in it.
    public init?(
        _ payload: NotificationPayload,
        in techniques: [Technique],
        tier: SubscriptionTier
    ) {
        guard let technique = techniques.first(where: { $0.slug == payload.techniqueSlug })
        else { return nil }

        self = technique.isUnlocked(for: tier) ? .session(technique) : .offer(technique)
    }
}

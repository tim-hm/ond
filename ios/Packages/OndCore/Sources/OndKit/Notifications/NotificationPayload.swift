import Foundation

/// What a notification carries besides its words: which exercise it is for.
/// Attached when it is scheduled and read back when it is tapped. Recovering
/// the exercise from the request identifier instead would point into state
/// that can move or be deleted in the days before it fires. A slug, not a
/// schedule id, because a server push names no schedule.
public struct NotificationPayload: Sendable, Equatable {
    /// The key the slug travels under, in both directions.
    ///
    /// Private, because one spelling on the sending side and another on the
    /// receiving side is a bug that only appears on a device, days later, when a
    /// reminder finally fires.
    private static let techniqueSlugKey = "techniqueSlug"

    /// The exercise to open, by the slug the catalogue keeps stable.
    public let techniqueSlug: TechniqueSlug

    public init(techniqueSlug: TechniqueSlug) {
        self.techniqueSlug = techniqueSlug
    }

    /// What to hand `UNMutableNotificationContent.userInfo`. Strings only: the
    /// notification centre and APNs both serialise this dictionary, so
    /// anything richer than a property-list scalar can fail to decode.
    public var userInfo: [String: String] {
        [Self.techniqueSlugKey: techniqueSlug.rawValue]
    }

    /// Reads a payload back off a tapped notification, or nil where there is
    /// none: a reminder placed before this shipped, or a notification that was
    /// never about an exercise. It takes iOS's own `[AnyHashable: Any]` so the
    /// one cast in the round trip stays where a host test can reach it.
    public init?(userInfo: [AnyHashable: Any]) {
        guard let slug = userInfo[Self.techniqueSlugKey] as? String, !slug.isEmpty else {
            return nil
        }
        techniqueSlug = TechniqueSlug(rawValue: slug)
    }
}

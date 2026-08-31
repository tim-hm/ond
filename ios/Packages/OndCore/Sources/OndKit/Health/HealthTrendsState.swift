import Foundation

/// What the check-ins screen draws where the watch's own trends go.
/// `nothingReadable` is the case this type exists for: an opt-in that did
/// nothing observable used to be indistinguishable from one that worked. It
/// still does not distinguish refusal from absence, and must not — HealthKit
/// does not report a denied read, and "nothing readable" is true of both.
public enum HealthTrendsState: Sendable, Equatable {
    /// The opt-in has not been given. Nothing has been asked of Health.
    case off
    /// Opted in, and the first read has not answered yet.
    case loading
    /// Opted in, with at least one metric Health had enough to summarise.
    case trends(CoachHealthContext)
    /// Opted in, and Health yielded nothing to summarise.
    case nothingReadable
}

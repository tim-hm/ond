import Foundation

/// What the check-ins screen draws where the watch's own trends go.
///
/// [`HealthTrendsState/nothingReadable`] is the case this type exists for. A
/// person who turned the opt-in on and then refused Health's own sheet — or who
/// has no watch, or has worn it for two days — used to get a switch that read
/// "on" and did nothing observable, forever, with no way to tell. Naming that
/// state is what lets the screen say so.
///
/// It still does not distinguish refusal from absence, and must not: HealthKit
/// does not report a denied read, and inferring one from silence would be this
/// app guessing at something Apple deliberately withholds. "Nothing readable"
/// is true of both, which is why it is the honest name for one case rather than
/// two.
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

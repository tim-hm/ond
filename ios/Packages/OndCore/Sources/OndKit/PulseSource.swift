import Foundation

/// The wearer's heart rate, as the sensor takes it.
///
/// Its own seam rather than a member of `HealthStore`, because it is a different
/// kind of thing from everything there. Those are pull queries over a date window
/// that any implementation can answer; this is a continuous subscription to
/// hardware, it exists on exactly one of the two platforms, and it carries a
/// precondition the seam cannot state — something has to be holding a workout
/// session open, or the sensor samples every few minutes instead of every few
/// seconds.
///
/// It was briefly a defaulted `HealthStore` requirement returning an empty
/// stream, and that was worse for the reason this whole feature is delicate:
/// silence is its designed failure mode, so a conformance that quietly inherited
/// "no readings" would be indistinguishable from no watch, no grant, and a wrist
/// on a bedside table. A separate seam with no default means a type either
/// answers this question deliberately or cannot be asked it.
public protocol PulseSource: Sendable {
    /// Readings from now until the stream is dropped, newest as they arrive.
    ///
    /// Asks for whatever grant it needs itself, because it is the only thing that
    /// wants one and because the answer changes nothing it could report: HealthKit
    /// never discloses a refused read, so a refusal and a wrist nobody is wearing
    /// are the same empty stream.
    func readings() async -> AsyncStream<HeartRateSample>
}

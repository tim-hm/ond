import Foundation

/// The wearer's heart rate, as the sensor takes it. Its own seam, not a
/// `HealthStore` member: a continuous hardware subscription with a precondition
/// — something must hold a workout session open, or the sensor samples every
/// few minutes. Deliberately no defaulted conformance: silence is the designed
/// failure mode, and a quietly inherited empty stream reads as no watch at all.
public protocol PulseSource: Sendable {
    /// Readings from now until the stream is dropped. Asks for whatever grant
    /// it needs itself: HealthKit never discloses a refused read, so a refusal
    /// and a wrist nobody is wearing are the same empty stream.
    func readings() async -> AsyncStream<HeartRateSample>
}

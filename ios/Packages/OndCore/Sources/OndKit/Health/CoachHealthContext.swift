import Foundation

/// Everything the coach may be told about what this person's watch has
/// measured: one coarse summary per metric, any of which may be absent when
/// Health had too little to say. Never constructed with all three absent — no
/// summary at all is `nil` at the `HealthContextModel.context()` boundary, so a
/// request either carries evidence or carries nothing.
public struct CoachHealthContext: Sendable, Equatable {
    /// Sleeping respiratory rate, in breaths a minute — the one measurement
    /// trials actually show breathing practice moves; the other two are
    /// context. A separate series from the counted rate and never to be
    /// compared with it: everybody breathes slower asleep, so the two disagree
    /// for reasons that have nothing to do with practice.
    public let sleepingBreathingRate: HealthSnapshot?

    /// Resting heart rate, in beats per minute.
    public let restingHeartRate: HealthSnapshot?

    /// Heart-rate variability (SDNN), in milliseconds.
    public let heartRateVariability: HealthSnapshot?

    public init(
        sleepingBreathingRate: HealthSnapshot?,
        restingHeartRate: HealthSnapshot?,
        heartRateVariability: HealthSnapshot?
    ) {
        self.sleepingBreathingRate = sleepingBreathingRate
        self.restingHeartRate = restingHeartRate
        self.heartRateVariability = heartRateVariability
    }
}

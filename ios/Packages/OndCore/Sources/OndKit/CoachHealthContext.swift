import Foundation

/// Everything the coach may be told about what this person's watch has
/// measured: one coarse summary per metric, any of which may be absent when
/// Health had too little to say. Never constructed with all three absent — no
/// summary at all is `nil` at the `HealthContextModel.context()` boundary, so a
/// request either carries evidence or carries nothing.
public struct CoachHealthContext: Sendable, Equatable {
    /// Sleeping respiratory rate, in breaths a minute.
    ///
    /// First because it is the passive companion to the rate the check-in has
    /// somebody count by hand — the one measurement in the app that trials
    /// actually show breathing practice moves. The other two are context for
    /// how the body has been running; this one is the practice's own subject.
    ///
    /// A separate series from the counted rate and never to be compared with
    /// it: everybody breathes slower asleep, so the two figures disagree for
    /// reasons that have nothing to do with practice.
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

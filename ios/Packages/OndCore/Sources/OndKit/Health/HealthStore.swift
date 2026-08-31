import Foundation

/// One day of a health metric, as the daily series queries answer: the start of
/// the day it summarises, and that day's average in the metric's display unit —
/// beats per minute for resting heart rate, milliseconds for HRV.
public struct DailyQuantity: Sendable, Equatable {
    public let day: Date
    public let value: Double

    /// Creates a daily reading when Health supplied a real quantity.
    /// HealthKit's numeric bridge is a `Double`, so the type admits NaN and
    /// infinities even though neither describes a measurement; refusing them
    /// here keeps invalid inputs out of later means and summaries.
    public init?(day: Date, value: Double) {
        guard value.isFinite else { return nil }
        self.day = day
        self.value = value
    }
}

/// One reading folded over a span of time: the window Health was asked about
/// and the average it answered with. The window is carried rather than an
/// index, so a caller matches by *when* rather than by position — a batch
/// that skips empty windows would silently shift every later answer onto the
/// wrong session.
public struct WindowedQuantity: Sendable, Equatable {
    public let window: DateInterval
    public let value: Double

    /// Creates a reading when Health supplied a real quantity — `DailyQuantity`'s
    /// refusal, for its reason: HealthKit's numeric bridge admits NaN and the
    /// infinities, and neither describes a measurement.
    public init?(window: DateInterval, value: Double) {
        guard value.isFinite else { return nil }
        self.window = window
        self.value = value
    }
}

/// One heart-rate reading: the moment it was taken and the rate in beats per
/// minute. What `PulseSource` streams, and the only shape a live reading
/// takes anywhere above that seam.
public struct HeartRateSample: Sendable, Equatable {
    public let date: Date
    public let beatsPerMinute: Double

    public init(date: Date, beatsPerMinute: Double) {
        self.date = date
        self.beatsPerMinute = beatsPerMinute
    }
}

/// Everything this app needs from HealthKit, and nothing else — the seam
/// that keeps the deciding logic testable without a paired device. Reads
/// never distinguish "denied" from "no data": both answer an empty series,
/// preserving HealthKit's own design. Writes each ask for their own grant,
/// with no ordering contract between calls — a third write could forget it.
public protocol HealthStore: Sendable {
    /// Asks the person for read access to the heart metrics. Shows the system
    /// sheet at most once; every later call resolves quietly. No answer comes
    /// back — see the note on reads above.
    func requestReadAuthorization() async

    /// Asks for the Mindful Minutes write grant ahead of any session, so the
    /// sheet lands on the screen that offered the switch rather than on
    /// somebody who just finished breathing. Additive: the write still
    /// requests its own grant, so nothing breaks when this is never called.
    func requestMindfulWriteAuthorization() async

    /// Daily respiratory rate over `[start, end)`, in breaths a minute, oldest
    /// first; empty on the terms above. A *sleeping* rate in practice — the
    /// watch samples breathing overnight and at no other time — so it is
    /// never the same series as the check-in's counted rate.
    func respiratoryRate(from start: Date, to end: Date) async -> [DailyQuantity]

    /// Daily resting heart rate over `[start, end)`, in beats per minute,
    /// oldest first. Empty for no data, no access, or no Health store at all.
    func restingHeartRate(from start: Date, to end: Date) async -> [DailyQuantity]

    /// Daily heart-rate variability (SDNN) over `[start, end)`, in
    /// milliseconds, oldest first. Empty on the same terms as above.
    func heartRateVariability(from start: Date, to end: Date) async -> [DailyQuantity]

    /// The average heart rate across each of `windows`, in beats per minute.
    /// A batch of windows rather than a range of samples, by design: the
    /// caller says which spans it is entitled to ask about, one number comes
    /// back for each, and no raw sample crosses this seam. Sparse — an empty
    /// window yields no entry — and unordered: match on the reading's window.
    func averageHeartRate(inEachOf windows: [DateInterval]) async -> [WindowedQuantity]

    /// Records the span from `start` to `end` as Mindful Minutes.
    ///
    /// Never fails from the caller's point of view: Health is an enhancement,
    /// and there is nothing a person who just finished breathing can do about a
    /// declined write except be needlessly told about it.
    func writeMindfulSession(from start: Date, to end: Date) async

    /// Records `mood` as a momentary State of Mind at `date`. Silent on
    /// refusal. Returns once the write — including the first-time system
    /// sheet — has been attempted, because the one caller that asks before a
    /// session starts must not let a countdown run underneath a modal.
    func writeMood(_ mood: Mood, at date: Date) async

    /// Whether writing a mood can still put Health's authorization sheet on
    /// screen — true only while the grant is undecided. The countdown holds
    /// itself for that one answer and counts through every later one, so a
    /// session neither starts behind a modal nor restarts for nothing.
    func writeMoodMayPrompt() async -> Bool
}

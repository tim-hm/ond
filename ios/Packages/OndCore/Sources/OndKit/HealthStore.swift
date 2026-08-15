import Foundation

/// One day of a health metric, as the daily series queries answer: the start of
/// the day it summarises, and that day's average in the metric's display unit —
/// beats per minute for resting heart rate, milliseconds for HRV.
public struct DailyQuantity: Sendable, Equatable {
    public let day: Date
    public let value: Double

    /// Creates a daily reading when Health supplied a real quantity.
    ///
    /// HealthKit's numeric bridge is a `Double`, so the type admits NaN and
    /// infinities even though neither describes a measurement. Refusing them at
    /// this seam keeps those invalid inputs out of later means and whole-number
    /// summaries.
    ///
    /// - Parameters:
    ///   - day: the start of the day HealthKit aggregated.
    ///   - value: that day's average in the metric's display unit.
    public init?(day: Date, value: Double) {
        guard value.isFinite else { return nil }
        self.day = day
        self.value = value
    }
}

/// One heart-rate reading: the moment it was taken and the rate in beats per
/// minute. What `PulseSource` streams, and the only shape a live reading takes
/// anywhere above that seam.
///
/// It lives here rather than beside `PulseSource` because it is the shape a
/// *reading* takes whoever asks for one, and this is where the rest of the
/// vocabulary Health answers in already is.
public struct HeartRateSample: Sendable, Equatable {
    public let date: Date
    public let beatsPerMinute: Double

    public init(date: Date, beatsPerMinute: Double) {
        self.date = date
        self.beatsPerMinute = beatsPerMinute
    }
}

/// Everything this app needs from HealthKit, and nothing else.
///
/// A seam for the same reason `StoreFront` is one: what the app *decides* from a
/// series of daily readings — the means, the trends, the evidence thresholds —
/// is the interesting logic, and none of it should need a paired device and a
/// populated Health store to exercise. `HealthKitHealthStore` is the only type
/// in the repository that imports `HealthKit`.
///
/// Reads never distinguish "denied" from "no data". That is HealthKit's own
/// design — an app is not told it was refused read access, it simply reads
/// nothing — and this protocol preserves it deliberately: both cases answer an
/// empty series, so nothing built on top can say "you denied access" to
/// somebody who did, or wrongly promise data to somebody who merely has none.
///
/// Writes ask for their own grant, each for its own sample type: a person who
/// agreed to Mindful Minutes has not thereby agreed to State of Mind, and the
/// separation is what keeps a second sheet from riding in on the first. There
/// is deliberately no write-authorization member to call beforehand — an
/// ordering contract between two calls is a rule a third write can forget, and
/// a forgotten one refuses silently.
public protocol HealthStore: Sendable {
    /// Asks the person for read access to the heart metrics. Shows the system
    /// sheet at most once; every later call resolves quietly. No answer comes
    /// back — see the note on reads above.
    func requestReadAuthorization() async

    /// Daily respiratory rate over `[start, end)`, in breaths a minute, oldest
    /// first. Empty on the same terms as above.
    ///
    /// A *sleeping* rate in practice, and every surface that shows it says so.
    /// An Apple Watch samples breathing overnight and at no other time, so a
    /// day's entry is the night that started it — which is why this is the
    /// passive companion to the rate somebody counts sitting still in the
    /// check-in, and never the same series: everybody breathes slower asleep.
    func respiratoryRate(from start: Date, to end: Date) async -> [DailyQuantity]

    /// Daily resting heart rate over `[start, end)`, in beats per minute,
    /// oldest first. Empty for no data, no access, or no Health store at all.
    func restingHeartRate(from start: Date, to end: Date) async -> [DailyQuantity]

    /// Daily heart-rate variability (SDNN) over `[start, end)`, in
    /// milliseconds, oldest first. Empty on the same terms as above.
    func heartRateVariability(from start: Date, to end: Date) async -> [DailyQuantity]

    /// Records the span from `start` to `end` as Mindful Minutes.
    ///
    /// Never fails from the caller's point of view: Health is an enhancement,
    /// and there is nothing a person who just finished breathing can do about a
    /// declined write except be needlessly told about it.
    func writeMindfulSession(from start: Date, to end: Date) async

    /// Records `mood` as a momentary State of Mind at `date`.
    ///
    /// Silent on refusal, on the terms above. Returns once the write has been
    /// attempted — including the system sheet, the first time — because the one
    /// caller that asks before a session starts must not let a countdown run
    /// underneath a modal nobody can see past.
    func writeMood(_ mood: Mood, at date: Date) async
}

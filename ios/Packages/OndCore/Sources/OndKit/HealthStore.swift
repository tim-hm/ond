import Foundation

/// One day of a health metric, as the daily series queries answer: the start of
/// the day it summarises, and that day's average in the metric's display unit —
/// beats per minute for resting heart rate, milliseconds for HRV.
public struct DailyQuantity: Sendable, Equatable {
    public let day: Date
    public let value: Double

    public init(day: Date, value: Double) {
        self.day = day
        self.value = value
    }
}

/// One heart-rate reading: the moment it was taken and the rate in beats per
/// minute. What `HealthStore.heartRate()` streams, and the only shape a live
/// reading takes anywhere above the seam.
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

    /// Readings as the sensor takes them, from now until the stream is dropped.
    ///
    /// The wrist's, and only the wrist's: a phone has no sensor, and the samples
    /// a watch writes reach a phone's Health store minutes late, which is a
    /// history rather than a pulse. Something has to be keeping a workout session
    /// running for readings to arrive at all — that is what makes the sensor
    /// sample continuously — and this seam does not arrange one.
    ///
    /// Asks for the read grant itself, because it is the only thing that wants
    /// one and because the answer changes nothing it could report: a refusal is
    /// indistinguishable from a wrist nobody is wearing, exactly as the note on
    /// reads above describes. Both are a stream that finishes having yielded
    /// nothing.
    ///
    /// Defaulted to exactly that, which is the truthful answer for every
    /// implementation but the one holding HealthKit on a watch — a phone has no
    /// sensor, and neither has a test double. It is the one member here worth a
    /// default: the others answer a question every implementation can answer, and
    /// this one asks for hardware.
    func heartRate() async -> AsyncStream<HeartRateSample>

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

public extension HealthStore {
    func heartRate() async -> AsyncStream<HeartRateSample> {
        AsyncStream { $0.finish() }
    }
}

import Foundation
import Observation

/// Everything the coach may be told about this person's heart: one coarse
/// summary per metric, either of which may be absent when Health had too
/// little to say. Never constructed with both absent — no summary at all is
/// `nil` at the `HealthContextModel.context()` boundary, so a request either
/// carries evidence or carries nothing.
public struct CoachHealthContext: Sendable, Equatable {
    /// Resting heart rate, in beats per minute.
    public let restingHeartRate: HealthSnapshot?

    /// Heart-rate variability (SDNN), in milliseconds.
    public let heartRateVariability: HealthSnapshot?

    public init(restingHeartRate: HealthSnapshot?, heartRateVariability: HealthSnapshot?) {
        self.restingHeartRate = restingHeartRate
        self.heartRateVariability = heartRateVariability
    }
}

/// What the check-ins screen draws where the heart trends go.
///
/// [`HeartTrendsState/nothingReadable`] is the case this type exists for. A
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
public enum HeartTrendsState: Sendable, Equatable {
    /// The opt-in has not been given. Nothing has been asked of Health.
    case off
    /// Opted in, and the first read has not answered yet.
    case loading
    /// Opted in, with at least one metric Health had enough to summarise.
    case trends(CoachHealthContext)
    /// Opted in, and Health yielded nothing to summarise.
    case nothingReadable
}

/// The in-app opt-in and the summary it unlocks: whether the coach may see
/// heart trends, and — only while it may — the coarse context a request
/// attaches.
///
/// The opt-in is deliberately a second switch on top of HealthKit's own
/// authorization, not a proxy for it. HealthKit never tells an app it was
/// refused read access — it simply reads nothing — and this model preserves
/// that on purpose: a denied grant and an empty Health store both fold to a
/// `nil` context, so nothing downstream can tell them apart, show a different
/// card, or say "you denied access". The only state this model owns is the
/// person's own in-app choice.
///
/// It also draws that summary for the person it describes — see
/// [`HeartTrendsState`], which is what stops the opt-in being a switch with no
/// observable effect.
///
/// `UserDefaults` for the toggle, following `SessionSettings`: it is a
/// preference, not history — and unlike most preferences it must never move
/// onto the profile, because the server keeping "who shares heart data" would
/// be the first health-adjacent fact it stores.
@MainActor
@Observable
public final class HealthContextModel: PersonalStore {
    /// How far back the daily series reach: eight weeks, enough history for
    /// `HealthSummaryBuilder` to clear its trend thresholds with room while
    /// staying a bounded, cheap pair of queries.
    private static let historyDays = 56

    private static let optInKey = "health.coachReadsHeartTrends"

    /// The in-app opt-in. Switching it on asks Health for read access —
    /// that is the first moment the app has any reason to read, and asking
    /// earlier would show a heart-data sheet to people who never opted in.
    public var coachReadsHeartTrends: Bool {
        didSet {
            defaults.set(coachReadsHeartTrends, forKey: Self.optInKey)
            guard coachReadsHeartTrends else {
                heartTrends = .off
                return
            }
            // The read follows the ask in the same task, so the screen that
            // offered the switch fills in behind the system sheet rather than
            // waiting to be visited again.
            authorizationRequest = Task {
                await store.requestReadAuthorization()
                await loadHeartTrends()
            }
        }
    }

    /// What the check-ins screen draws. Read there, and nowhere else — the
    /// coach's own copy comes from [`context()`], which is asked per request so
    /// that withdrawing the opt-in takes effect on the next question rather than
    /// on the next launch.
    public private(set) var heartTrends: HeartTrendsState = .off

    /// The in-flight authorization ask, held so a test can await its
    /// completion — `didSet` cannot suspend, so the request runs as a task.
    /// Internal and unobserved: it is a test seam, not view state.
    @ObservationIgnored private(set) var authorizationRequest: Task<Void, Never>?

    private let store: any HealthStore
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date

    /// `now` is injectable so the folding is a pure function of the spy's
    /// series in host tests; the default is the clock.
    public init(
        store: any HealthStore,
        defaults: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.defaults = defaults
        self.now = now
        // Assigning in an initialiser does not run `didSet`, so restoring the
        // stored choice neither rewrites it nor re-asks Health for access.
        coachReadsHeartTrends = defaults.bool(forKey: Self.optInKey)
    }

    /// Withdraws the opt-in, and forgets that it was ever given.
    ///
    /// The only state this model owns, and the only one it could erase — nothing
    /// read from Health is ever stored, here or on the server. Switching it off
    /// does not revoke HealthKit's own grant, which is Apple's to hold and the
    /// person's to withdraw in Health; what it does is stop this app asking, and
    /// a request made after this carries no heart context at all.
    public func erase() async {
        coachReadsHeartTrends = false
        defaults.removeObject(forKey: Self.optInKey)
    }

    /// The context a coach request should carry right now: both metrics'
    /// series folded through `HealthSummaryBuilder`, or nil when the opt-in is
    /// off or Health yielded nothing — in which case the request goes exactly
    /// as it would have before this feature existed.
    public func context() async -> CoachHealthContext? {
        guard coachReadsHeartTrends else { return nil }

        let end = now()
        let start = end.addingTimeInterval(-TimeInterval(Self.historyDays) * 86400)

        // Concurrently: two independent Health queries, both sitting in front
        // of the coach request they contextualise — serialised, the second
        // round trip to the health daemon would be added straight to the time
        // before the question is even sent.
        async let restingSeries = store.restingHeartRate(from: start, to: end)
        async let variabilitySeries = store.heartRateVariability(from: start, to: end)
        let restingHeartRate = await HealthSummaryBuilder.snapshot(of: restingSeries, asOf: end)
        let heartRateVariability = await HealthSummaryBuilder.snapshot(
            of: variabilitySeries,
            asOf: end
        )

        guard restingHeartRate != nil || heartRateVariability != nil else { return nil }
        return CoachHealthContext(
            restingHeartRate: restingHeartRate,
            heartRateVariability: heartRateVariability
        )
    }

    /// Reads the same summary the coach gets, for the person it is about.
    ///
    /// Showing it back is what makes the opt-in honest. Before this, the only
    /// evidence the switch did anything was whether a coach reply happened to
    /// mention it — so a grant refused at Health's own sheet looked exactly like
    /// a grant that worked, and stayed that way.
    ///
    /// Nothing is cached beyond the drawn state: the promise is that heart data
    /// is never stored, and a value held past the screen that showed it would be
    /// storage by another name.
    public func loadHeartTrends() async {
        guard coachReadsHeartTrends else {
            heartTrends = .off
            return
        }

        // Only from `off`, so revisiting the screen redraws the numbers already
        // in hand rather than blanking them for the length of two Health
        // queries.
        if heartTrends == .off {
            heartTrends = .loading
        }

        heartTrends = if let context = await context() {
            .trends(context)
        } else {
            .nothingReadable
        }
    }
}

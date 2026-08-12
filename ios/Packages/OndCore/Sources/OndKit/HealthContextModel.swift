import Foundation
import Observation

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

/// The in-app opt-in and the summary it unlocks: whether the coach may see what
/// the person's watch has measured, and — only while it may — the coarse
/// context a request attaches.
///
/// The opt-in is deliberately a second switch on top of HealthKit's own
/// authorization, not a proxy for it. HealthKit never tells an app it was
/// refused read access — it simply reads nothing — and this model preserves
/// that on purpose: a denied grant and an empty Health store both fold to a
/// `nil` context, so nothing downstream can tell them apart, show a different
/// card, or say "you denied access". The only state this model owns is the
/// person's own in-app choices — this read opt-in, and the write-side switch
/// beside it.
///
/// It also draws that summary for the person it describes — see
/// [`HealthTrendsState`], which is what stops the opt-in being a switch with no
/// observable effect.
///
/// `UserDefaults` for the toggle, following `SessionSettings`: it is a
/// preference, not history — and unlike most preferences it must never move
/// onto the profile, because the server keeping "who shares health data" would
/// be the first health-adjacent fact it stores.
@MainActor
@Observable
public final class HealthContextModel: PersonalStore {
    /// How far back the daily series reach: eight weeks, enough history for
    /// `HealthSummaryBuilder` to clear its trend thresholds with room while
    /// staying a bounded, cheap set of queries.
    private static let historyDays = 56

    private static let optInKey = "health.coachReadsHealthTrends"

    /// Where "this app owes Health an authorization request" is remembered
    /// across launches. See [`adopt(readsTrends:)`].
    private static let pendingAuthorizationKey = "health.pendingReadAuthorization"

    /// The in-app opt-in. Switching it on asks Health for read access —
    /// that is the first moment the app has any reason to read, and asking
    /// earlier would show a health-data sheet to people who never opted in.
    public var coachReadsHealthTrends: Bool {
        didSet {
            defaults.set(coachReadsHealthTrends, forKey: Self.optInKey)
            guard coachReadsHealthTrends else {
                healthTrends = .off
                return
            }
            // Onboarding collects this switch among three others and promises
            // that none of them shows a system sheet; it owes the ask instead.
            guard !isAdopting else { return }
            // The read follows the ask in the same task, so the screen that
            // offered the switch fills in behind the system sheet rather than
            // waiting to be visited again.
            authorizationRequest = Task {
                await store.requestReadAuthorization()
                await loadHealthTrends()
            }
        }
    }

    /// Whether the assignment above came from [`adopt(readsTrends:)`] rather
    /// than from somebody moving the switch. The one thing it suppresses is the
    /// ask; the preference is written either way.
    @ObservationIgnored private var isAdopting = false

    /// Whether a kept session is credited to Health as Mindful Minutes — the
    /// write-side mirror of the opt-in above, owned here for the same reason:
    /// it is the person's in-app choice, never the server's to hold. On by
    /// default, and no task on flipping it: write access is asked at record
    /// time, by `MindfulMinutesRecorder`, which also reads this preference.
    public var writesMindfulMinutes: Bool {
        didSet {
            defaults.set(writesMindfulMinutes, forKey: MindfulMinutesRecorder.preferenceKey)
        }
    }

    /// What the check-ins screen draws. Read there, and nowhere else — the
    /// coach's own copy comes from [`context()`], which is asked per request so
    /// that withdrawing the opt-in takes effect on the next question rather than
    /// on the next launch.
    public private(set) var healthTrends: HealthTrendsState = .off

    /// The in-flight authorization ask, held so a test can await its
    /// completion — `didSet` cannot suspend, so the request runs as a task.
    /// Internal and unobserved: it is a test seam, not view state.
    @ObservationIgnored private(set) var authorizationRequest: Task<Void, Never>?

    private let store: any HealthStore
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date

    /// What the person is entitled to, read afresh at every read of Health.
    ///
    /// The subscription lives here rather than at the two call sites, and that
    /// placement is the point: reading somebody's HRV is special-category data
    /// under GDPR Art. 9, so "no read happens below the tier" has to be a
    /// property of the thing that reads rather than a rule each caller
    /// remembers. A lapsed subscriber whose opt-in is still on is exactly the
    /// case a call-site check would miss — the switch is their preference and
    /// stays theirs, and it is this that stops it being acted on.
    ///
    /// Not applied to [`writesMindfulMinutes`], which is free at every tier and
    /// goes nowhere near this model's reads.
    ///
    /// Defaulted to `.free` rather than to the convenient answer: a composition
    /// that forgot to wire this degrades a subscriber's coach, where the
    /// opposite would read health data on behalf of somebody who is not paying
    /// for it, which is the failure that matters.
    private let entitledTier: @MainActor () -> SubscriptionTier

    /// `now` is injectable so the folding is a pure function of the spy's
    /// series in host tests; the default is the clock.
    public init(
        store: any HealthStore,
        defaults: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = { Date() },
        entitledTier: @escaping @MainActor () -> SubscriptionTier = { .free }
    ) {
        self.store = store
        self.defaults = defaults
        self.now = now
        self.entitledTier = entitledTier
        // Assigning in an initialiser does not run `didSet`, so restoring the
        // stored choices neither rewrites them nor re-asks Health for access.
        coachReadsHealthTrends = defaults.bool(forKey: Self.optInKey)
        writesMindfulMinutes = MindfulMinutesRecorder.writesToHealth(in: defaults)
    }

    /// Takes the read opt-in as onboarding collected it, without asking Health
    /// for anything yet.
    ///
    /// Onboarding puts this switch beside three others on one screen and says
    /// in its own footer that nothing there summons a system sheet. Honouring
    /// that is the whole of this method: the preference is stored exactly as
    /// the switch in Settings would store it, and the authorization it implies
    /// is written down as owed rather than asked for.
    ///
    /// The debt is paid at the first genuine read — see
    /// [`resolvePendingAuthorization()`] — which is the first coach question or
    /// the first visit to the trends card. That is also the first moment the
    /// sheet is explicable, which is the point: a Health dialog over a
    /// four-switch setup screen asks somebody to decide about data the app has
    /// not yet given them a reason to share.
    ///
    /// Kept across launches, because somebody may finish onboarding and not
    /// ask the coach anything for a week.
    public func adopt(readsTrends: Bool) {
        isAdopting = true
        coachReadsHealthTrends = readsTrends
        isAdopting = false

        if readsTrends {
            defaults.set(true, forKey: Self.pendingAuthorizationKey)
        } else {
            // Removed rather than set to false: onboarding's promise is that
            // skipping every switch leaves an install indistinguishable from
            // one that was never set up, and a key written with the default
            // value is still a key.
            defaults.removeObject(forKey: Self.pendingAuthorizationKey)
        }
    }

    /// Withdraws the read opt-in, forgets it was ever given, and returns the
    /// Mindful Minutes write to its default of on.
    ///
    /// The two switches are the only state this model owns, and the only state
    /// it could erase — nothing read from Health is ever stored, here or on the
    /// server. Erasing revokes nothing at HealthKit, whose grants are Apple's
    /// to hold and the person's to withdraw in Health; what it does is stop
    /// this app asking, and a request made after this carries no heart context
    /// at all.
    public func erase() async {
        coachReadsHealthTrends = false
        writesMindfulMinutes = true
        defaults.removeObject(forKey: Self.optInKey)
        defaults.removeObject(forKey: MindfulMinutesRecorder.preferenceKey)
        defaults.removeObject(forKey: Self.pendingAuthorizationKey)
    }

    /// The context a coach request should carry right now: both metrics'
    /// series folded through `HealthSummaryBuilder`, or nil when the opt-in is
    /// off or Health yielded nothing — in which case the request goes exactly
    /// as it would have before this feature existed.
    public func context() async -> CoachHealthContext? {
        guard isReadable else { return nil }
        await resolvePendingAuthorization()

        let end = now()
        let start = end.addingTimeInterval(-TimeInterval(Self.historyDays) * 86400)

        // Concurrently: three independent Health queries, all sitting in front
        // of the coach request they contextualise — serialised, each further
        // round trip to the health daemon would be added straight to the time
        // before the question is even sent.
        async let breathingSeries = store.respiratoryRate(from: start, to: end)
        async let restingSeries = store.restingHeartRate(from: start, to: end)
        async let variabilitySeries = store.heartRateVariability(from: start, to: end)
        let sleepingBreathingRate = await HealthSummaryBuilder.snapshot(
            of: breathingSeries,
            asOf: end
        )
        let restingHeartRate = await HealthSummaryBuilder.snapshot(of: restingSeries, asOf: end)
        let heartRateVariability = await HealthSummaryBuilder.snapshot(
            of: variabilitySeries,
            asOf: end
        )

        guard sleepingBreathingRate != nil
            || restingHeartRate != nil
            || heartRateVariability != nil
        else {
            return nil
        }
        return CoachHealthContext(
            sleepingBreathingRate: sleepingBreathingRate,
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
    /// Nothing is cached beyond the drawn state: the promise is that health data
    /// is never stored, and a value held past the screen that showed it would be
    /// storage by another name.
    public func loadHealthTrends() async {
        guard isReadable else {
            healthTrends = .off
            return
        }

        // Only from `off`, so revisiting the screen redraws the numbers already
        // in hand rather than blanking them for the length of two Health
        // queries.
        if healthTrends == .off {
            healthTrends = .loading
        }

        healthTrends = if let context = await context() {
            .trends(context)
        } else {
            .nothingReadable
        }
    }

    /// Pays the authorization [`adopt(readsTrends:)`] deferred, if one is owed.
    ///
    /// Behind [`isReadable`], deliberately: an opt-in given at onboarding by
    /// somebody who never subscribes is a preference the app holds and never
    /// acts on, and showing them a Health sheet for a read that will not happen
    /// would be the worst of both. The subscription arriving later is what
    /// makes the first read — and so this ask — happen at all.
    ///
    /// The flag is cleared before the ask rather than after, so two reads
    /// racing here produce one sheet. The cost of that ordering is an ask lost
    /// to a crash mid-sheet; HealthKit's own grant survives it, and the read
    /// that follows simply returns nothing until somebody visits the trends
    /// card, whose switch asks outright.
    private func resolvePendingAuthorization() async {
        guard defaults.bool(forKey: Self.pendingAuthorizationKey) else { return }

        defaults.removeObject(forKey: Self.pendingAuthorizationKey)
        await store.requestReadAuthorization()
    }

    /// Whether Health may be read at all: the person asked for it, and they are
    /// paying for the thing that reads it.
    ///
    /// Both halves, in one place, because they fail the same way and must not
    /// be checked separately — the two read paths would then be two chances to
    /// check one and not the other.
    private var isReadable: Bool {
        coachReadsHealthTrends && entitledTier() >= .healthTrends
    }
}

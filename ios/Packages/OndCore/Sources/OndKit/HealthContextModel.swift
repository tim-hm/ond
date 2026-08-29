import Foundation
import Observation

/// The in-app opt-in and the summary it unlocks: whether the coach may see
/// what the watch has measured. A second switch on top of HealthKit's own
/// authorization: HealthKit never says it was refused, so a denied grant and
/// an empty store both fold to a nil context. The toggle stays in
/// `UserDefaults`, never on the profile — the server must not hold it.
@MainActor
@Observable
public final class HealthContextModel: PersonalStore {
    /// How far back the daily series reach: eight weeks, enough history for
    /// `HealthSummaryBuilder` to clear its trend thresholds with room while
    /// staying a bounded, cheap set of queries.
    private static let historyDays = 56

    private static let optInKey = "health.coachReadsHealthTrends"

    /// The in-app opt-in — one switch for every read of heart data there is:
    /// the coach's context and the heart rate Home draws. The name is narrower
    /// than what it grants but is the stored defaults key. Storing it asks
    /// Health for nothing: the writers want different combinations of
    /// preference and ask, and a setter that raised a sheet would surprise.
    public var coachReadsHealthTrends: Bool {
        didSet {
            defaults.set(coachReadsHealthTrends, forKey: Self.optInKey)
            if !coachReadsHealthTrends {
                healthTrends = .off
                blankPracticeHeart()
            }
        }
    }

    /// Asks Health for read access, and fills the trends in behind the sheet.
    /// Called straight after turning the opt-in on — the first moment the app
    /// has any reason to read; earlier would show a health-data sheet to
    /// people who never opted in. The read follows the ask in the same task,
    /// so the screen fills in rather than waiting to be visited again.
    public func requestReadAccess() {
        authorizationRequest = Task {
            await store.requestReadAuthorization()
            await loadHealthTrends()
        }
    }

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

    /// What the check-ins screen draws — the coach's own copy comes from [`context()`],
    /// which is asked per request so that withdrawing the opt-in takes effect
    /// on the next question rather than on the next launch.
    public private(set) var healthTrends: HealthTrendsState = .off

    /// When the last trends read finished — see [`loadHealthTrends()`].
    /// Unobserved: the drawn state is [`healthTrends`], and this is only the
    /// plumbing under it.
    @ObservationIgnored private var trendsReadAt: Date?

    /// How long a drawn answer serves new askers before Health is asked again:
    /// long enough to cover a mount's pre-read/re-read pair and a burst of tab
    /// hops, short enough that "read when you open this" stays true. Both read
    /// paths honour it, and only for an answer they actually drew.
    private static let readFreshness: TimeInterval = 60

    /// Your heart rate around the last few practices, or nil while nothing is
    /// worth drawing. One optional rather than a state machine: not read yet,
    /// not allowed, no watch and too few readings all end as a card simply not
    /// on screen. The trends card has states because it is also where the
    /// feature is *offered*; this one is not offered anywhere.
    public private(set) var practiceHeart: PracticeHeartline?

    /// The practices the drawn heartline was folded from, so a second ask about
    /// the same sessions inside the freshness window does not go back to Health.
    /// Unobserved: plumbing under [`practiceHeart`].
    @ObservationIgnored private var practiceHeartFor: [UUID] = []

    /// When the last heart read finished — see [`loadPracticeHeart(from:)`].
    @ObservationIgnored private var practiceHeartReadAt: Date?

    /// The in-flight authorization ask, held so a test can await its
    /// completion — `didSet` cannot suspend, so the request runs as a task.
    /// Internal and unobserved: it is a test seam, not view state.
    @ObservationIgnored private(set) var authorizationRequest: Task<Void, Never>?

    private let store: any HealthStore
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date

    /// What the person is entitled to, read afresh at every read of Health.
    /// The check lives on the thing that reads, not at call sites: HRV is
    /// special-category data under GDPR Art. 9, and a lapsed subscriber whose
    /// opt-in is still on is exactly what a call-site check would miss.
    /// Defaults to `.free` — a mis-wired composition must degrade, not read.
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

    /// Asks Health for the grants two switches stand for, and nothing they
    /// are off for. Told what the switches say rather than reading this
    /// model's own properties, because the preferences are written in the same
    /// breath as this call. Sequential: each is a system sheet, and two raised
    /// at once is one nobody sees. `readsTrends` is asked even at free tier.
    public func requestGrants(readsTrends: Bool, writesMinutes: Bool) async {
        if writesMinutes {
            await store.requestMindfulWriteAuthorization()
        }
        if readsTrends {
            await store.requestReadAuthorization()
        }
    }

    /// Withdraws the read opt-in and returns the Mindful Minutes write to its
    /// default of on — the only state this model owns; nothing read from
    /// Health is ever stored. Erasing revokes nothing at HealthKit, whose
    /// grants are the person's to withdraw in Health; it stops this app
    /// asking, and a request made after this carries no heart context at all.
    public func erase() async {
        coachReadsHealthTrends = false
        writesMindfulMinutes = true
        defaults.removeObject(forKey: Self.optInKey)
        defaults.removeObject(forKey: MindfulMinutesRecorder.preferenceKey)
    }

    /// The context a coach request should carry right now: both metrics'
    /// series folded through `HealthSummaryBuilder`, or nil when the opt-in is
    /// off or Health yielded nothing — in which case the request goes exactly
    /// as it would have before this feature existed.
    public func context() async -> CoachHealthContext? {
        guard isReadable else { return nil }

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

    /// Reads the same summary the coach gets, for the person it is about —
    /// showing it back is what makes the opt-in honest. Nothing is cached
    /// beyond the drawn state: health data is never stored. A drawn answer
    /// under a minute old serves the next asker; only a `.trends` answer is
    /// served this way, so a fresh opt-in is not answered with a stale read.
    public func loadHealthTrends() async {
        guard isReadable else {
            healthTrends = .off
            return
        }

        if case .trends = healthTrends, isFresh(trendsReadAt) {
            return
        }

        // Only from `off`, so revisiting the screen redraws the numbers already
        // in hand rather than blanking them for the length of two Health
        // queries.
        if healthTrends == .off {
            healthTrends = .loading
        }

        let context = await context()

        // The world can move while Health answers: an opt-out or a lapse
        // mid-flight must win over the read it interrupted, or the model
        // would draw trends the person has just declined to share.
        guard isReadable else {
            healthTrends = .off
            return
        }

        healthTrends = if let context {
            .trends(context)
        } else {
            .nothingReadable
        }
        trendsReadAt = now()
    }

    /// Reads the heart rate around each of the last few practices in
    /// `history`. **Nothing is stored** — readings are folded into whole beats
    /// and the samples discarded. Freshness is keyed on both a minute's
    /// elapsed time and the practices asked about: time alone would hide a
    /// session finished twenty seconds ago, exactly when somebody looks.
    public func loadPracticeHeart(from history: [SessionRecord]) async {
        guard isReadable else {
            blankPracticeHeart()
            return
        }

        let practices = PracticeHeartline.practices(in: history, now: now())
        guard !practices.isEmpty else {
            blankPracticeHeart()
            return
        }

        // Only a *drawn* answer is served from the cache, which is the half of
        // `loadHealthTrends`' rule that matters here: a heartline blanked by a
        // lapse mid-read leaves the stamp behind, and without this the tier
        // coming back inside the minute would be answered with the nil.
        let asked = practices.map(\.id)
        if isFresh(practiceHeartReadAt), asked == practiceHeartFor, practiceHeart != nil {
            return
        }

        let readings = await store.averageHeartRate(
            inEachOf: practices.map(PracticeHeartline.heartWindow(around:))
        )

        // A cancelled read is a *partial* read; committing one would be a
        // false statement about somebody's health data. The store swallows
        // cancellation into a nil per window, so nothing is committed and
        // nothing stamped — the next visit reads again.
        guard !Task.isCancelled else { return }

        // The world can move while Health answers, on `loadHealthTrends()`'s
        // reasoning: an opt-out or a lapse mid-flight wins over the read it
        // interrupted.
        guard isReadable else {
            blankPracticeHeart()
            return
        }

        let heartline = PracticeHeartline(practices: practices, readings: readings, now: now())
        practiceHeart = heartline.isWorthDrawing ? heartline : nil
        practiceHeartFor = asked
        practiceHeartReadAt = now()
    }

    /// Drops the drawn heartline *and* the stamp that would serve it again —
    /// the two go together or the cache outlives what it describes. The tier
    /// is read live, so a lapse and recovery inside one minute is ordinary.
    private func blankPracticeHeart() {
        practiceHeart = nil
        practiceHeartFor = []
        practiceHeartReadAt = nil
    }

    /// Whether a read that finished at `readAt` still serves a new asker.
    private func isFresh(_ readAt: Date?) -> Bool {
        readAt.map { now().timeIntervalSince($0) < Self.readFreshness } ?? false
    }

    /// Whether Health may be read at all: the person asked for it, and they
    /// are paying for the thing that reads it. Both halves in one place — the
    /// two read paths would otherwise be two chances to check one and not the
    /// other.
    private var isReadable: Bool {
        coachReadsHealthTrends && entitledTier() >= .healthTrends
    }
}

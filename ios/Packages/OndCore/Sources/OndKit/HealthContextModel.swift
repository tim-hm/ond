import Foundation
import Observation

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

    /// The in-app opt-in, and nothing but the opt-in — one switch for every
    /// read of heart data there is: the coach's context, and the heart rate
    /// Home draws around each practice. One rather than two because a second
    /// would be a second `isReadable` to get wrong, and because "which of my
    /// two health switches is this" is not a question to hand somebody.
    ///
    /// The name is narrower than what it grants and is kept anyway: it is the
    /// defaults key somebody's answer is stored under.
    ///
    /// Storing it asks Health for nothing. The two are separate decisions and
    /// the writers want different combinations of them — Settings' switch asks
    /// on the spot ([`requestReadAccess()`]), onboarding writes the preference
    /// and asks alongside it ([`requestGrants(readsTrends:writesMinutes:)`]),
    /// and a restore or a migration wants no ask at all. Welded to the setter,
    /// every one of those raises a HealthKit sheet as a side effect of an
    /// assignment, which is how a system dialog ends up over a screen nobody
    /// expected it on.
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
    ///
    /// Called straight after turning the opt-in on from a screen somebody is
    /// looking at — that is the first moment the app has any reason to read,
    /// and asking earlier would show a health-data sheet to people who never
    /// opted in. The read follows the ask in the same task, so the screen that
    /// offered the switch fills in behind the sheet rather than waiting to be
    /// visited again.
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

    /// How long a drawn answer — the coach's trends, or the heart around a
    /// practice — serves new askers before Health is asked again. Long enough to
    /// cover a mount's pre-read/re-read pair and a burst of tab hops; short
    /// enough that "read when you open this" stays true for any deliberate
    /// visit. Both read paths honour it, and only for an answer they actually
    /// drew.
    private static let readFreshness: TimeInterval = 60

    /// Your heart rate around the last few sessions you practised, or nil while
    /// there is nothing worth drawing.
    ///
    /// One optional rather than a state machine like [`healthTrends`], because
    /// there is nothing here worth telling anybody apart: not read yet, not
    /// allowed to look, no watch on your wrist and too few readings to say
    /// anything all end in the same place, which is a card that is simply not
    /// on the screen. The trends card has states because it is also where the
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

    /// Asks Health for the grants two switches stand for, and for nothing they
    /// are off for.
    ///
    /// Onboarding's, and told what the switches say rather than reading this
    /// model's own properties: the preferences are written in the same breath
    /// as this call, and a method that read them back would depend on which of
    /// the two ran first. What the screen collected is the answer either way.
    ///
    /// Sequential rather than concurrent because each is a system sheet, and
    /// two raised at once is one nobody sees.
    ///
    /// - Parameters:
    ///   - readsTrends: whether the coach may read the watch's measurements.
    ///     Asked even at the free tier, where no read will happen until
    ///     somebody subscribes: the switch is off unless they turned it on, and
    ///     an explicit yes is what this is answering.
    ///   - writesMinutes: whether kept sessions are credited as Mindful Minutes.
    public func requestGrants(readsTrends: Bool, writesMinutes: Bool) async {
        if writesMinutes {
            await store.requestMindfulWriteAuthorization()
        }
        if readsTrends {
            await store.requestReadAuthorization()
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
    ///
    /// A drawn answer under a minute old serves the next asker without going
    /// back to Health. The check-ins card asks on mount and every hop back to
    /// the screen asks once more — one set of queries covers them all, as a
    /// property of the thing that reads, so no pair of surfaces has to
    /// coordinate. Only a `.trends` answer is served this
    /// way: an empty or withdrawn state re-asks, so an opt-in granted a
    /// moment ago is not answered with the read that preceded it.
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

    /// Reads the heart rate around each of the last few practices in `history`.
    ///
    /// **Nothing is stored.** The readings are folded into whole beats and the
    /// samples discarded here, which is the promise the whole feature rests on:
    /// a heart rate is health data, `PulseTrace` states that a live one is
    /// deliberately not on the record that reaches the server, and a summary
    /// held past the screen that drew it would be storage by another name.
    ///
    /// Freshness is keyed on **both** a minute's elapsed time and the practices
    /// asked about. Time alone would hide a session finished twenty seconds ago
    /// behind the read that preceded it — which is exactly when somebody looks.
    ///
    /// - Parameter history: every session on this device, in any order. The
    ///   window and the ten it draws are `PracticeHeartline`'s to decide, so the
    ///   read is scoped to what will be drawn rather than to a stretch of
    ///   somebody's life.
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

        // A cancelled read is a *partial* read, and committing one would be a
        // false statement about somebody's health data. The store answers one
        // window at a time and its boundary swallows cancellation into a nil per
        // window, so a tab hop three windows in leaves seven practices looking
        // exactly like seven practices breathed without a watch on. Nothing is
        // committed and nothing is stamped, so the next visit reads again.
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

    /// Drops the drawn heartline *and* the stamp that would serve it again.
    ///
    /// The two go together or the cache outlives what it describes: the opt-in's
    /// own `didSet` clears both, and every other road to a blank card has to do
    /// the same — the tier is read live, so a lapse and a recovery inside one
    /// minute is an ordinary sequence rather than an exotic one.
    private func blankPracticeHeart() {
        practiceHeart = nil
        practiceHeartFor = []
        practiceHeartReadAt = nil
    }

    /// Whether a read that finished at `readAt` still serves a new asker.
    private func isFresh(_ readAt: Date?) -> Bool {
        readAt.map { now().timeIntervalSince($0) < Self.readFreshness } ?? false
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

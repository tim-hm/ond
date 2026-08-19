import Foundation
import Observation

/// Drives the first-run stepper: which screen is up, what has been answered,
/// what the answers switch on, and when the flow is done with somebody.
///
/// Lives in `OndKit` rather than the app target so the flow is testable on
/// the host — the app target has no test bundle, and a stepper whose transitions
/// nobody can exercise is where a screen someone cannot get past comes from.
@MainActor
@Observable
public final class OnboardingModel {
    public private(set) var step: Step = .welcome

    /// Whether the flow is done with this person.
    ///
    /// A flag rather than a final step, because there is nothing left to draw:
    /// the cover the flow lives in dismisses on this, and a screen whose only
    /// content was a button to leave was charging a tap for nothing.
    public private(set) var isFinished = false

    /// What to call this person, as typed.
    ///
    /// Narrowed as it is typed by the same rule `Profile.clampedToServerLimits()`
    /// applies on the way out — length, and the control characters the server
    /// refuses a name for — so the field stops accepting input rather than
    /// letting somebody paste something that saves locally and is then refused
    /// on every launch for the life of the install.
    ///
    /// Trimmed on the way onto the profile rather than here, so a space typed
    /// between two words survives being typed.
    public var givenName: String = "" {
        didSet {
            let clamped = givenName.clampedName(toScalars: Profile.maxGivenNameLength)
            if clamped != givenName {
                givenName = clamped
            }
        }
    }

    /// In the order they were picked, which is the order they are shown back.
    public private(set) var goals: [TechniqueGoal] = []
    public var experienceLevel: ExperienceLevel?

    /// Where the reminder dial arrives, which is a proposal rather than the
    /// silence it used to be.
    ///
    /// `daily` rather than `never`: a reminder is the difference between an app
    /// installed once and a practice, and the row on screen states its own
    /// position — so somebody who wants no reminder is one tap from saying so,
    /// and nothing is seeded behind their back. It is the one default in this
    /// flow that asks iOS for something, and the notification prompt is raised
    /// on the way out of the screen that shows it.
    public var reminderIntensity: ReminderIntensity = .daily {
        didSet { hasMovedDial = true }
    }

    /// Whether the dial above was moved by a person rather than merely arrived
    /// at its default. Read by [`hasAnswered`], and by nothing else — what is
    /// *stored* is the dial's position either way.
    private var hasMovedDial = false

    /// The switches as they stand on screen. Nothing is written anywhere until
    /// the step is left — see [`applyOptIns()`].
    public var optIns: OptIns

    /// The switches as this flow found them, kept so that only what somebody
    /// actually moved is ever written back.
    ///
    /// A `let` rather than something updated as the step is left: the forward
    /// exit can run twice — `optIns`, Back to `you`, forward again — and
    /// comparing against the values the flow *started* from makes the second
    /// pass apply the same diffs to the same stores, which is a no-op. A
    /// baseline moved on the first pass would make the second one see no
    /// change at all, which is the same answer by luck rather than by rule.
    let arrived: OptIns

    /// What the server already held for this identity, when the answer arrived
    /// too late to close the flow — see [`restoreIfPossible()`].
    ///
    /// Kept as the base the answers are merged over rather than discarded,
    /// because `UpdateProfile` replaces every column: without it, finishing a
    /// flow that never asks for a display name or a gender is what erases one.
    private var restoredBase: Profile?

    private let store: ProfileStore
    private let catalogue: TechniqueListModel?
    private let consent: SafetyConsentStore
    /// These three are internal rather than private only because the opt-ins
    /// step's own two methods live in the file beside this one.
    let schedules: ScheduleStore?
    let settings: SessionSettings?
    let health: HealthContextModel?
    private let plus: SubscriptionStore?

    /// - Parameters:
    ///   - schedules: where a reminder the person asked for lands. Absent, the
    ///     dial is still stored on the profile and simply rings nothing.
    ///   - catalogue: what that reminder opens with. Also absent-able, and for
    ///     the same reason: onboarding has to finish with no network, and the
    ///     catalogue is a fetch.
    ///   - consent: where agreement to the safety terms is recorded. The one
    ///     collaborator here with no optional form and no do-nothing default: a
    ///     consent step that records nothing satisfies nothing, and an app
    ///     composing this without one would look identical until somebody asked
    ///     what a person had agreed to.
    ///   - settings: where two of the four switches live. Absent, the screen
    ///     still draws them and leaving it writes nothing.
    ///   - health: where the other two live, and the one collaborator that
    ///     needs telling *how* it was asked — see [`applyOptIns()`].
    ///   - plus: what this person is already entitled to, which is the whole of
    ///     the trial step's reason to exist. **No default**, unlike every
    ///     optional collaborator above: absent, this flow offers önd+ to
    ///     somebody who already pays for it, and that is a mistake worth making
    ///     a caller state rather than inherit. Passing `nil` is a composition
    ///     saying there is no subscription behind it.
    ///   - startingAt: the screen the flow opens on. The screenshot harness
    ///     names a later one to photograph, which runs none of its predecessors.
    public init(
        store: ProfileStore,
        schedules: ScheduleStore? = nil,
        catalogue: TechniqueListModel? = nil,
        consent: SafetyConsentStore = SafetyConsentStore(),
        settings: SessionSettings? = nil,
        health: HealthContextModel? = nil,
        plus: SubscriptionStore?,
        startingAt: Step = .welcome
    ) {
        step = startingAt
        self.store = store
        self.schedules = schedules
        self.catalogue = catalogue
        self.consent = consent
        self.settings = settings
        self.health = health
        self.plus = plus

        var optIns = OptIns.freshInstall
        if let settings {
            optIns.asksHowYouFeel = settings.asksHowYouFeel
            optIns.showsWristPulse = settings.showsWristPulse
        }
        if let health {
            optIns.coachReadsHealthTrends = health.coachReadsHealthTrends
            optIns.writesMindfulMinutes = health.writesMindfulMinutes
        }
        self.optIns = optIns
        arrived = optIns
    }

    /// The safety terms this flow puts on screen.
    public var safetyTerms: SafetyConsent {
        consent.terms
    }

    /// Whether this person already holds önd+.
    ///
    /// The one statement of the rule the trial step turns on, read live from
    /// the store rather than snapshotted: a purchase made *on* that step moves
    /// the tier and nothing else reports it, so the screen watches this and
    /// calls `advance()` — the same shape as the paywall dismissing itself, and
    /// the reason that rule is not written out a second time in the view.
    public var isEntitled: Bool {
        (plus?.tier ?? .free) >= .plus
    }

    /// The steps this person will see, in the order the progress indicator draws them.
    ///
    /// Derived rather than the static list, because a subscriber never sees the
    /// offer: including a step [`advance()`] hops over would leave a dot
    /// unreachable and have VoiceOver announce a total nobody will get to. A
    /// trial already on screen stays in the list for the brief handover after a
    /// purchase, because visible content still needs a current step until the
    /// entitlement observation advances it.
    public var progressSteps: [Step] {
        Step.allCases.filter { step in
            step != .trial || !isEntitled || self.step == .trial
        }
    }

    /// Whether this person has told the flow anything yet.
    ///
    /// Asked of the profile the answers make rather than field by field, so the
    /// question a restore turns on and the question asked of the server's copy
    /// are the same one — and a fourth question cannot make them disagree.
    ///
    /// The dial is put back where `Profile.unanswered` holds it unless somebody
    /// moved it. `profile` carries the dial's *proposal* like every other
    /// answer, and it has to — that is what gets stored — but a default nobody
    /// touched is not something they told us, and treating it as one would
    /// report every fresh install as answered and so skip the restore this
    /// question exists to gate.
    public var hasAnswered: Bool {
        var answered = profile
        if !hasMovedDial {
            answered.reminderIntensity = Profile.unanswered.reminderIntensity
        }
        return answered.hasAnswers
    }

    /// Adopts the answers the server already holds for this identity, closing
    /// the flow if it finds them.
    ///
    /// Runs *alongside* the questions rather than in front of them. The
    /// alternative — racing the fetch against a short timeout before drawing
    /// anything — puts a network wait between launch and the welcome screen for
    /// every genuinely new user, which is nearly all of them and none of whom
    /// have a profile to restore. Here the flow is on screen immediately, and
    /// somebody with no signal never learns this was attempted.
    ///
    /// Answers arriving after the flow has moved on are merged rather than
    /// dropped, which is the half of this that is not about closing the screen.
    /// The flow asks about four things and `UpdateProfile` replaces all seven,
    /// so a display name, a gender or a birth band that only the server held is
    /// erased by finishing — the answers here are the more recent, but
    /// answering them was never a withdrawal of the ones nobody was asked.
    ///
    /// - Returns: whether the flow should close, having adopted a profile.
    public func restoreIfPossible() async -> Bool {
        guard !hasAnswered else { return false }
        guard let restored = await store.restoredProfile() else { return false }

        // Asked again on the way back: the request was in flight while the
        // person could answer, and an answer given here is both the more recent
        // of the two and the one they are looking at.
        let isTooLate = hasAnswered || store.hasCompletedOnboarding
        restoredBase = restored

        guard isTooLate else {
            store.adopt(restored)
            return true
        }

        // Where the flow finished under the fetch, the save has already gone
        // out with blanks in it. This is the write that repairs it; where the
        // flow is only part-way through, the base above is enough and the
        // ordinary save on the way out of the opt-ins carries it.
        if store.hasCompletedOnboarding {
            await store.save(profile)
        }
        return false
    }

    /// Adds or removes a goal, keeping the order the person picked in.
    public func toggle(_ goal: TechniqueGoal) {
        if let index = goals.firstIndex(of: goal) {
            goals.remove(at: index)
        } else {
            goals.append(goal)
        }
    }

    public func isSelected(_ goal: TechniqueGoal) -> Bool {
        goals.contains(goal)
    }

    /// Whether the current step can be passed by without engaging with it — the
    /// four steps a Skip is drawn on.
    ///
    /// It does the same thing Next does, and the label is the difference: on
    /// these four, moving past is a complete answer and the word should say so.
    /// The safety terms alone remain a wall.
    public var canSkip: Bool {
        Step.skippable.contains(step)
    }

    /// Whether there is a screen behind this one to return to.
    ///
    /// Every screen after Welcome except the safety wall. Going back from the
    /// offer may revisit already-stored answers, but applying their same diff a
    /// second time is idempotent and preserves the platform-standard route back.
    ///
    /// Back from `you` reaches the welcome, which is fine: it is a page to
    /// re-read rather than a place to be part-way through, and it refuses Back
    /// in turn.
    public var canGoBack: Bool {
        step == .you || step == .optIns || step == .trial
    }

    /// Moves on: everything that happens on the way out of a step, and then the
    /// step change itself.
    ///
    /// Two phases rather than one save at the end, and the split is
    /// load-bearing. The answers are stored on the way out of `optIns`, so a
    /// person who quits the app on the trial or the safety screen relaunches
    /// into the safety-only gate rather than into the whole flow again —
    /// `FirstRunGate` reads exactly the two records these two phases write.
    ///
    /// The reminder is seeded in the second phase, at the end, because seeding
    /// it needs the catalogue — the schedule opens with a technique — and on a
    /// first launch that fetch may still be in the air two screens earlier. The
    /// notification prompt no longer waits with it: `requestOptInGrants()`
    /// raises that over the dial that asked for it, and `ScheduleStore.add`
    /// asking again here resolves quietly.
    ///
    /// Nothing is required of any step, so there is no state this refuses in —
    /// the one screen that cannot be passed by refuses `skip` rather than
    /// holding this back, because its button is an agreement and pressing it
    /// has to move.
    public func advance() {
        if step == .optIns {
            store.complete(with: profile)
            applyOptIns()
            // Not awaited: the person is a tap or two from breathing, and the
            // upload has a whole app lifetime to succeed in. `ProfileStore` has
            // already written the answers and closed onboarding by this point.
            Task { await store.syncIfNeeded() }
        }

        if step == .safety {
            // Written on the way out of the step rather than when the screen
            // appears, because pressing the button is the agreement — reaching
            // the screen is not.
            consent.record()
            seedReminder()
            isFinished = true
            return
        }

        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        step = next

        // Nobody is sold what they already have. Somebody who reinstalls with a
        // live subscription meets the trial screen with nothing on it they can
        // act on, so they never meet it.
        if step == .trial, isEntitled {
            advance()
        }
    }

    /// Passes a step by without engaging with it. The answers given so far are
    /// kept — skipping is declining to finish, not undoing — and the side
    /// effects of leaving a step happen either way, because leaving it is what
    /// they are attached to.
    ///
    /// Guarded rather than left to the view: the safety wall having no way
    /// around it is a rule, and a rule enforced only by a button not being
    /// drawn is a rule one refactor from being gone.
    public func skip() {
        guard canSkip else { return }
        advance()
    }

    /// Returns to the screen before, where there is one to return to.
    ///
    /// Guarded on [`canGoBack`] rather than trusting the chevron to be absent,
    /// for the reason [`skip()`] is guarded: "you cannot go back past the save"
    /// is a rule about what this flow has already stored and sent, and a rule
    /// held up only by a button not being drawn is one refactor from gone.
    public func back() {
        guard canGoBack, let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    /// Makes the reminder the stored dial position implies.
    ///
    /// The work is `ReminderDial.seedIfNeeded()`'s rather than this type's,
    /// because first run has two exits and only one of them is here: somebody
    /// who quit after the answers were stored comes back to the safety terms
    /// alone, with no `OnboardingModel` anywhere near them. One idempotent seed
    /// read off the profile is what makes "a dial off `never` has a schedule"
    /// true on both.
    ///
    /// Not awaited, so the person is still one tap from breathing — the dial
    /// waits on the catalogue fetch, which on a first launch may still be in
    /// the air.
    private func seedReminder() {
        guard let schedules, let catalogue else { return }
        let dial = ReminderDial(profiles: store, schedules: schedules, catalogue: catalogue)

        Task { await dial.seedIfNeeded() }
    }

    /// The answers as they stand, laid over whatever the profile already holds.
    ///
    /// An overlay rather than a fresh `Profile`, and that is load-bearing:
    /// `UpdateProfile` replaces every column, so a value constructed from the
    /// four things this flow asks about carries blanks in the other three — and
    /// sending it erases a display name, a gender and a birth band the server
    /// was holding for somebody reinstalling. Building it from the stored
    /// profile means a field this flow does not ask about survives by default,
    /// including any field added after this was written.
    ///
    /// The three absent from the list below are absent on purpose: the display
    /// name is the leaderboard screen's, and the birth band, gender and note
    /// are Settings' — every one of them still editable there, and none worth a
    /// screen between somebody and their first breath.
    ///
    /// Narrowed on the way out rather than field by field, so what this
    /// property returns is always something the server will accept.
    public var profile: Profile {
        var merged = restoredBase ?? store.profile
        merged.goals = goals
        merged.experienceLevel = experienceLevel
        merged.reminderIntensity = reminderIntensity
        merged.givenName = givenName.trimmingCharacters(in: .whitespacesAndNewlines)
        return merged.clampedToServerLimits()
    }
}

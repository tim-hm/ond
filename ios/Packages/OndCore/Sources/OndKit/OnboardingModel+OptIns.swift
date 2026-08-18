import Foundation

public extension OnboardingModel {
    /// The four switches onboarding collects, as one value.
    ///
    /// Together rather than as four properties because they are read, compared
    /// and applied as a set: [`OnboardingModel/applyOptIns()`] writes only what
    /// moved, and a baseline to compare against is a second copy of exactly
    /// this shape.
    struct OptIns: Sendable, Equatable {
        /// Whether a session asks how you feel, before and after.
        public var asksHowYouFeel: Bool
        /// Whether a session shows a live heart rate from the watch.
        public var showsWristPulse: Bool
        /// Whether önd may read heart data from Health at all: the coach's
        /// context between sessions, and the heart rate Home draws around each
        /// practice. Paywalled, and asked for anyway when it is on — see
        /// [`OnboardingModel/requestOptInGrants()`].
        ///
        /// The name is narrower than what it now grants, and deliberately kept:
        /// it is the key somebody's stored answer is written under, and renaming
        /// it would silently reset every existing opt-in to off.
        public var coachReadsHealthTrends: Bool
        /// Whether a kept session is credited to Health as Mindful Minutes.
        public var writesMindfulMinutes: Bool

        /// What a fresh install holds.
        ///
        /// Reached only by a flow composed without the stores that own these,
        /// which is only ever a test: in the app both collaborators are
        /// present and their own values are read instead. Written out rather
        /// than derived because the stores keep their defaults private, and a
        /// test that had to construct two stores to learn them would be
        /// testing the wrong thing.
        public static let freshInstall = Self(
            asksHowYouFeel: true,
            showsWristPulse: false,
            coachReadsHealthTrends: false,
            writesMindfulMinutes: true
        )
    }
}

public extension OnboardingModel {
    /// Asks iOS for every permission the opt-ins step's answers imply, and for
    /// nothing they are off for.
    ///
    /// Run by the screen on the way out of that step, before [`advance()`], so
    /// each sheet is raised over the switch that explains it. Deferring them was
    /// the older stance — Apple asks for permissions in context, and the reading
    /// was that a switch is a preference and the *use* is the context. A switch
    /// somebody has just deliberately turned on is that context: the sheet
    /// arrives attached to the sentence they read, rather than days later at a
    /// moment nothing on screen accounts for. Each prompt is one-shot per
    /// install, which is the argument for asking where it is explicable and
    /// against asking for anything nobody switched on.
    ///
    /// The values come from what the screen holds rather than from the stores,
    /// because [`applyOptIns()`] writes those in the same breath and a read-back
    /// would depend on which ran first.
    ///
    /// The wrist grant is not here: `PulseMonitor` is the app's rather than this
    /// flow's, so `OnboardingView` asks for that one alongside this call.
    ///
    /// One sheet at a time — two raised together is one nobody sees — and the
    /// free tier still contributes a `coachReadsHealthTrends` ask, because an
    /// explicit yes to a paywalled switch is still an explicit yes.
    func requestOptInGrants() async {
        await health?.requestGrants(
            readsTrends: optIns.coachReadsHealthTrends,
            writesMinutes: optIns.writesMindfulMinutes
        )

        if reminderIntensity != .never {
            await schedules?.requestNotificationAuthorization()
        }
    }
}

extension OnboardingModel {
    /// Switches on what the opt-ins step collected, and only what moved.
    ///
    /// The comparison against the values the flow arrived to is the promise
    /// that somebody who taps straight through leaves no trace: each of these
    /// properties writes to `UserDefaults` on assignment, so applying all four
    /// unconditionally would leave a fresh install carrying four keys it would
    /// not otherwise have — which is a record of a decision nobody made.
    ///
    /// Preferences only. What they imply for HealthKit and notifications is
    /// [`requestOptInGrants()`], which the screen runs while it is still the one
    /// on screen — keeping the two apart is what lets a system sheet be awaited
    /// without the stored answers waiting on somebody's tap.
    ///
    /// Runs on the forward exit from the step, which can happen twice — Back to
    /// `you` and forward again. That is safe rather than merely unlikely: each
    /// comparison is against the values the flow started from, so the second
    /// pass writes the same values to the same stores.
    ///
    /// Internal rather than private only because it lives beside the type it
    /// belongs to rather than inside it; `advance()` is its one caller.
    func applyOptIns() {
        if optIns.asksHowYouFeel != arrived.asksHowYouFeel {
            settings?.asksHowYouFeel = optIns.asksHowYouFeel
        }
        if optIns.showsWristPulse != arrived.showsWristPulse {
            settings?.showsWristPulse = optIns.showsWristPulse
        }
        if optIns.writesMindfulMinutes != arrived.writesMindfulMinutes {
            health?.writesMindfulMinutes = optIns.writesMindfulMinutes
        }
        if optIns.coachReadsHealthTrends != arrived.coachReadsHealthTrends {
            health?.coachReadsHealthTrends = optIns.coachReadsHealthTrends
        }
    }
}

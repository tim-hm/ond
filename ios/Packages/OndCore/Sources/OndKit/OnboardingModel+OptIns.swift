import Foundation

public extension OnboardingModel {
    /// The four switches onboarding collects, as one value. They are read,
    /// compared and applied as a set: [`OnboardingModel/applyOptIns()`] writes
    /// only what moved, against a baseline of this same shape.
    struct OptIns: Sendable, Equatable {
        /// Whether a session asks how you feel, before and after.
        public var asksHowYouFeel: Bool
        /// Whether a session shows a live heart rate from the watch.
        public var showsWristPulse: Bool
        /// Whether önd may read heart data from Health: the coach's context,
        /// and the heart rate Home draws around each practice. Paywalled, and
        /// still asked for when on — see `requestOptInGrants()`. The name is
        /// narrower than what it grants, but it is the stored key: renaming it
        /// resets every opt-in to off.
        public var coachReadsHealthTrends: Bool
        /// Whether a kept session is credited to Health as Mindful Minutes.
        public var writesMindfulMinutes: Bool

        /// What a fresh install holds. Reached only by a flow composed without
        /// the stores that own these, which is only ever a test. Written out
        /// rather than derived because the stores keep their defaults private.
        public static let freshInstall = Self(
            asksHowYouFeel: true,
            showsWristPulse: false,
            coachReadsHealthTrends: false,
            writesMindfulMinutes: true
        )
    }
}

public extension OnboardingModel {
    /// Asks iOS for every permission the opt-ins answers imply, one sheet at a
    /// time, and for nothing they are off for. The screen runs it before
    /// [`advance()`], so each sheet sits over the switch that explains it. The
    /// values come from the screen, not the stores, which [`applyOptIns()`]
    /// writes in the same breath. `OnboardingView` asks for the wrist grant.
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
    /// Switches on what the opt-ins step collected, and only what moved. Each
    /// property writes to `UserDefaults` on assignment, so applying all four
    /// would leave a fresh install carrying four keys nobody chose. The
    /// comparison is against the values the flow arrived to, so a second pass
    /// after Back writes the same values. Grants are [`requestOptInGrants()`].
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

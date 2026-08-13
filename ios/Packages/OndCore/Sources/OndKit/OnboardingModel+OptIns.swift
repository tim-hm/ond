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
        /// Whether the coach may read what the watch has measured between
        /// sessions. The one switch here whose permission is deferred rather
        /// than merely late — see `HealthContextModel.adopt(readsTrends:)`.
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

extension OnboardingModel {
    /// Switches on what the opt-ins step collected, and only what moved.
    ///
    /// The comparison against the values the flow arrived to is the promise
    /// that somebody who taps straight through leaves no trace: each of these
    /// properties writes to `UserDefaults` on assignment, so applying all four
    /// unconditionally would leave a fresh install carrying four keys it would
    /// not otherwise have — which is a record of a decision nobody made.
    ///
    /// The health read opt-in goes through `adopt` rather than the property its
    /// switch in Settings writes: that one asks HealthKit for access in the
    /// same breath, and the step has promised in its own footer that nothing on
    /// it summons a system sheet.
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
        // Straight onto the property, because this one asks Health for nothing:
        // write access is requested at record time by `MindfulMinutesRecorder`.
        if optIns.writesMindfulMinutes != arrived.writesMindfulMinutes {
            health?.writesMindfulMinutes = optIns.writesMindfulMinutes
        }
        if optIns.coachReadsHealthTrends != arrived.coachReadsHealthTrends {
            health?.adopt(readsTrends: optIns.coachReadsHealthTrends)
        }
    }
}

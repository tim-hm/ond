import Foundation

public extension OnboardingModel {
    /// The screens, in the order they are shown.
    ///
    /// An enum with an ordinal rather than an index into an array of views: the
    /// progress indicator, the back button, and the save all need to know where
    /// they are, and a raw `Int` would let them disagree.
    ///
    /// Five, down from eight, and the cuts are the shape of the flow rather
    /// than a trim: the evidence stance folded into the welcome so the app's
    /// case for itself is made once, the four questions became two screens, and
    /// the closing "that's it" went — a screen whose only content is a button
    /// is a tap charged for nothing.
    enum Step: Int, CaseIterable, Identifiable, Sendable {
        /// What the app is, and what it will not claim. Says the science-first
        /// thing before asking for anything, because a stance stated after the
        /// questions reads as a disclaimer.
        case welcome

        /// The person: what to call them, what they came for, and how much they
        /// want explained. Nothing here is required — every part of it has a
        /// valid unanswered state, and Next takes them all.
        case you

        /// The four switches and the reminder dial, in front of somebody
        /// rather than behind Settings.
        ///
        /// Front-loaded on purpose, and the permissions its answers imply are
        /// asked for on the way out of it — over the switches that explain
        /// them, and only for what is switched on. See
        /// [`OnboardingModel/applyOptIns()`] for the preferences and
        /// [`OnboardingModel/requestOptInGrants()`] for the grants.
        case optIns

        /// The önd+ trial, offered once and passed by with "Not now".
        ///
        /// After the opt-ins rather than before them, so the first thing this
        /// app asks somebody for is not money — and after the save, so a person
        /// who quits on the price has still finished onboarding.
        case trial

        /// The safety terms, and the one thing in this flow nobody may pass by.
        ///
        /// Last, immediately before the first session, because that is where a
        /// warning is worth most — the same argument that used to keep a caution
        /// on the exercise screens, applied once. `Skip` refuses it.
        case safety

        public var id: Self {
            self
        }

        /// The first four screens may be passed by. Welcome's Skip is the route
        /// for somebody who already understands the product; `safety` remains a
        /// condition of use with no way around it.
        ///
        /// What a progress indicator counts is
        /// [`OnboardingModel/progressSteps`] instead: every visible screen,
        /// minus the offer a subscriber never meets.
        public static let skippable: [Step] = [.welcome, .you, .optIns, .trial]
    }
}

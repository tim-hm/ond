import Foundation

/// How a session is made, and the one gate on making one.
///
/// Split from the body of ``SessionModel`` because constructing a session and
/// running one are different jobs with different readers: every surface that can
/// start something reads this file, and none of them needs the cue loop. The
/// designated initialiser stays with the class, where a class's must be, so this
/// costs no property its `private`.
public extension SessionModel {
    /// A session on the clock a session actually runs on.
    ///
    /// The public way in, and the reason ``SessionClock`` is not public: a
    /// session outside a test has exactly one clock, and the suite that has to
    /// assert on where the plan is reaches the internal initialiser instead.
    convenience init(
        technique: Technique,
        cues: any SessionCueing,
        recorder: any SessionRecording,
        register: CopyRegister = .plain,
        occasionSlug: String? = nil
    ) {
        self.init(
            technique: technique,
            cues: cues,
            recorder: recorder,
            clock: SystemClock(),
            register: register,
            occasionSlug: occasionSlug
        )
    }

    /// A session, if this person's tier opens this technique.
    ///
    /// The catalogue lock's one choke point. It sits here rather than on each
    /// button because a session can be started from four places — the
    /// catalogue, the detail screen, home's dial, and the watch — and a rule
    /// asked at the button is a rule the fifth place will forget. Two of them
    /// already had.
    ///
    /// `nil` rather than a thrown error: "they have not paid for this" is not a
    /// failure to report, it is a different screen to show, and the caller
    /// already knows which.
    ///
    /// `register` and `occasionSlug` default, because only a route carries
    /// either: the catalogue, the coach and the watch all reach a session
    /// without them. `SessionStart` is the caller that undefaults both, on the
    /// surfaces where an occasion can arrive.
    static func starting(
        _ technique: Technique,
        for tier: SubscriptionTier,
        cues: any SessionCueing,
        recorder: any SessionRecording,
        register: CopyRegister = .plain,
        occasionSlug: String? = nil
    ) -> SessionModel? {
        guard technique.isUnlocked(for: tier) else { return nil }

        return Self(
            technique: technique,
            cues: cues,
            recorder: recorder,
            register: register,
            occasionSlug: occasionSlug
        )
    }
}

import Foundation

/// How a session is made. Apart from the body of ``SessionModel`` because
/// every surface that can start something reads this file, and none of them
/// needs the cue loop. The designated initialiser stays with the class, where
/// a class's must be, so this costs no property its `private`.
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
        occasionSlug: OccasionSlug? = nil,
        title: String? = nil,
        warning: SessionWarning? = nil
    ) {
        self.init(
            technique: technique,
            cues: cues,
            recorder: recorder,
            clock: SystemClock(),
            register: register,
            occasionSlug: occasionSlug,
            title: title,
            warning: warning
        )
    }
}

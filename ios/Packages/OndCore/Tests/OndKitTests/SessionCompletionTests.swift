@testable import OndKit
import Testing

/// A session may never simply stop. The screen is often off, so an ending
/// nobody felt is indistinguishable from a crash — the completion mark is
/// bounded rather than left to whenever the cue loop happens to wake.
@MainActor
@Suite("Ending a session so it is felt")
struct SessionCompletionTests {
    @Test("The completion mark lands inside its bound of the plan running out")
    func completionIsPrompt() async throws {
        let cues = RecordingCues()
        let model = SessionModel(
            technique: briefBreathing(cycles: 5),
            cues: cues,
            recorder: DiscardingRecorder()
        )

        let started = ContinuousClock.now
        model.start()
        try await waitFor("the completion mark") { cues.completions == 1 }

        #expect(
            started.duration(to: ContinuousClock.now)
                <= model.timeline.totalDuration + SessionModel.completionBound
        )
    }

    /// The bound is only worth stating if the loop's own wake-ups stay well
    /// inside it. An unstated tolerance is the system's to choose.
    @Test("One cue wake-up cannot spend the whole budget")
    func wakeUpsStayInsideTheBound() {
        #expect(SystemClock.tolerance < SessionModel.completionBound)
    }
}

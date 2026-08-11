import Foundation
import OndKit
import Testing

/// The rule that keeps the journal honest: a session ended by hand inside the
/// first ten seconds was a false start, and false starts are not practice.
@MainActor
@Suite("Discarding false starts")
struct SessionDiscardTests {
    @Test("Ending inside the first seconds records nothing")
    func discardsAQuickCancel() async throws {
        let recorder = CapturingRecorder()
        let model = SessionModel(
            technique: briefBreathing(cycles: 1000),
            cues: RecordingCues(),
            recorder: recorder
        )

        model.start()
        try await Task.sleep(for: .milliseconds(40))
        model.end()

        #expect(model.status == .finished)
        #expect(model.wasDiscarded)
        // The record still exists on the model — the discard is about the
        // journal, not about lying to the screen that just ended.
        #expect(model.record != nil)

        // The write is fired on a Task; give it a beat to have happened if it
        // wrongly would.
        try await Task.sleep(for: .milliseconds(50))
        #expect(recorder.recorded.isEmpty)
    }

    /// Finishing the plan is practice however short the plan was — the
    /// exemption that keeps a deliberately brief technique recordable.
    @Test("A completed session is kept however short it was")
    func keepsAShortCompletion() async throws {
        let recorder = CapturingRecorder()
        let model = SessionModel(
            technique: briefBreathing(cycles: 2),
            cues: RecordingCues(),
            recorder: recorder
        )

        model.start()
        try await waitFor("the plan to run out") { model.status == .finished }

        #expect(!model.wasDiscarded)
        #expect(model.record?.completed == true)

        // The write rides an unstructured Task; poll rather than assume it
        // has landed by the time the status flipped.
        for _ in 0 ..< 100 {
            if !recorder.recorded.isEmpty {
                break
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(recorder.recorded.count == 1)
    }
}

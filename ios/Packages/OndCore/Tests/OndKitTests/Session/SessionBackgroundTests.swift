import Foundation
@testable import OndKit
import Testing

/// What happens to a session when the app stops being looked at. Eyes closed
/// with the screen off is the posture these techniques are done in, so a
/// departure is only an interruption when the cues cannot follow. The session
/// asks the cue channel which it is; these pin both answers, and the one
/// thing true of either — a pause somebody reached for stays a pause.
@MainActor
@Suite("Backgrounding a session")
struct SessionBackgroundTests {
    @Test("A session whose cues play in the background is not stopped by leaving")
    func keepsRunningWhenTheCuesDo() async throws {
        let model = SessionModel(
            technique: briefBreathing(cycles: 1000),
            cues: RecordingCues(playsInBackground: true),
            recorder: DiscardingRecorder()
        )
        model.start()
        try await waitFor("the session to be running") { model.status == .running }

        model.pauseForScene()

        #expect(
            model.status == .running,
            "the phone going dark is the technique, not an interruption"
        )
    }

    /// The regression this issue exists for, stated as time: a session away for a
    /// while comes back to where the plan actually is, not where it left. Both
    /// halves matter — a frozen session reads short, one that counted the gap
    /// twice reads long. On a `ManualClock` because both failures sit a few
    /// milliseconds from right, and wall-clock slack was the size of the bug.
    @Test("Time away is time in the session, not time owed to it")
    func staysOnTheWallClock() async throws {
        let clock = ManualClock()
        let model = SessionModel(
            technique: briefBreathing(cycles: 1000),
            cues: RecordingCues(playsInBackground: true),
            recorder: DiscardingRecorder(),
            clock: clock
        )
        model.start()
        try await waitFor("the session to be running") { model.status == .running }

        let departed = model.elapsed
        model.pauseForScene()
        let away = Duration.milliseconds(200)
        clock.advance(by: away)
        model.resumeIfSceneDriven()

        #expect(
            model.elapsed - departed == away,
            "cues that play in the background make a departure no interruption at all"
        )
    }

    /// The `Done when:` clause that is about what did *not* change. Background
    /// runtime is a reason not to pause on a departure; it was never a reason to
    /// overrule the person, and a hand pause that undid itself because a banner
    /// dropped is the failure the scene flag exists to prevent.
    @Test("A hand pause survives a departure and a return")
    func leavesAHandPauseAlone() async throws {
        let model = SessionModel(
            technique: briefBreathing(cycles: 1000),
            cues: RecordingCues(playsInBackground: true),
            recorder: DiscardingRecorder()
        )
        model.start()
        try await waitFor("the session to be running") { model.status == .running }

        model.pause()
        model.pauseForScene()
        model.resumeIfSceneDriven()

        #expect(model.status == .paused)
    }

    /// The clause about being told, pinned at the only seam a host test can
    /// reach: the view posts a notification exactly when this says a departure
    /// stopped something. All three answers are wrong in a different way —
    /// silent-and-running is the point; sounding is a session that never stopped;
    /// hand-paused is a stop the person already knows about.
    @Test("Only a departure that stopped a running session is worth saying so")
    func reportsWhetherTheDepartureStoppedAnything() async throws {
        let silent = SessionModel(
            technique: briefBreathing(cycles: 1000),
            cues: RecordingCues(playsInBackground: false),
            recorder: DiscardingRecorder()
        )
        silent.start()
        try await waitFor("the silent session to be running") { silent.status == .running }
        #expect(silent.pauseForScene(), "a silent session stopped, and nothing else said so")

        let sounding = SessionModel(
            technique: briefBreathing(cycles: 1000),
            cues: RecordingCues(playsInBackground: true),
            recorder: DiscardingRecorder()
        )
        sounding.start()
        try await waitFor("the sounding session to be running") { sounding.status == .running }
        #expect(!sounding.pauseForScene(), "the cues followed them out; there is nothing to report")

        let handPaused = SessionModel(
            technique: briefBreathing(cycles: 1000),
            cues: RecordingCues(playsInBackground: false),
            recorder: DiscardingRecorder()
        )
        handPaused.start()
        try await waitFor("the paused session to be running") { handPaused.status == .running }
        handPaused.pause()
        #expect(!handPaused.pauseForScene(), "they paused it themselves and know that they did")
    }

    /// The answer the lock screen draws its Resume control on, pinned as an
    /// agreement rather than a value. A Live Activity offering to resume a
    /// session iOS suspends a second later offers something that cannot happen —
    /// so the control is withheld exactly where a departure would have stopped
    /// the session, and what breaks that is the two answers drifting apart.
    @Test("What a departure does to a session is what a surface outside it is told")
    func saysWhetherItFollowsYouOut() async throws {
        for reachable in [true, false] {
            let model = SessionModel(
                technique: briefBreathing(cycles: 1000),
                cues: RecordingCues(playsInBackground: reachable),
                recorder: DiscardingRecorder()
            )
            model.start()
            try await waitFor("the session to be running") { model.status == .running }

            #expect(model.followsYouOut == reachable)
            #expect(
                model.pauseForScene() == !model.followsYouOut,
                "a departure stops exactly the sessions that cannot be resumed from outside"
            )
        }
    }

    /// The other half of holding the app open: a pause has to give the runtime
    /// back. Left playing, a session somebody paused and walked away from would
    /// keep the phone awake for as long as they stayed away — the battery cost of
    /// a feature nobody is using.
    @Test("A pause hands the runtime back, and a resume takes it again")
    func releasesTheRuntimeWhilePaused() async throws {
        let cues = RecordingCues(playsInBackground: true)
        let model = SessionModel(
            technique: briefBreathing(cycles: 1000),
            cues: cues,
            recorder: DiscardingRecorder()
        )
        model.start()
        try await waitFor("the session to be running") { model.status == .running }

        model.pause()
        #expect(cues.pauses == 1)

        model.resume()
        // Two, not one: starting the session is itself a claim on the runtime,
        // and the resume is the second. What matters is that no pause goes
        // unanswered, not that the claims are minimal.
        #expect(cues.resumes == 2)
    }
}

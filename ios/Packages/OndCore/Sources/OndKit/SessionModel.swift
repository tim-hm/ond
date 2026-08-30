import Foundation
import Observation

/// Drives one session: the clock, the phase the person is in, and the record
/// left behind. The view and the cue loop both derive elapsed time by
/// subtracting from one anchor, so a late frame or wake-up is a late answer,
/// not a permanent offset. `elapsed` is a position in the plan; `realElapsed`
/// is wall time — an open-ended hold pins the plan, not the wall clock.
@MainActor
@Observable
public final class SessionModel {
    /// The technique as it is being played — already dialled, if the person
    /// dialled it (`Technique.dialled(with:)`). One answer to what this session
    /// is, so nothing downstream can read a duration the session never plays.
    public let technique: Technique
    /// What this launch is called. A protocol keeps its own name while the
    /// technique remains the exercise underneath it.
    public let title: String
    public let timeline: SessionTimeline
    /// The caution for this exact launch, including protocol-owned cautions
    /// that should not appear on direct starts of the same exercise.
    public let warning: SessionWarning?

    public private(set) var status: Status = .ready
    /// The beat the cue loop most recently entered. The view uses it for the
    /// phase label and the VoiceOver announcement; the animation reads the
    /// timeline directly instead, because it needs a value per frame rather than
    /// per boundary.
    public private(set) var currentBeat: SessionTimeline.Beat?
    /// Set once the session ends — the same value written to the session store,
    /// so the summary screen shows exactly what was recorded.
    public private(set) var record: SessionRecord?

    /// The stage this session earned, or nil where it earned none — almost
    /// every session. Lands a moment after `record`: the count comes from the
    /// store, so the screen introduces the line rather than being drawn with
    /// it. Counted from the sessions this device holds — a watch that has not
    /// restored can re-congratulate a rung — over saying nothing offline.
    public private(set) var reachedStage: PracticeStage?

    /// How long the cue hardware is held after a session ends — long enough
    /// for the completion cue, and no longer: `AVAudioSession` stays in
    /// `.playback` until `SessionCueing.stop()`, ducking everybody else's
    /// audio. A constant rather than the cue implementation's answer, which
    /// would cost `SessionCueing` an async `playCompletion()` in three targets.
    static let cueReleaseDelay: Duration = .seconds(2)

    private let cues: any SessionCueing
    private let recorder: any SessionRecording
    private let clock: any SessionClock
    /// The occasion that prescribed this session, stamped onto the record; nil
    /// for every start that was the person's own choice.
    private let occasionSlug: OccasionSlug?

    /// The instant both elapsed times are measured from. Nil while paused, which
    /// is what makes them hold still.
    private var anchor: ContinuousClock.Instant?
    /// Position in the plan banked by previous run segments. Pinned to a hold's
    /// start for as long as the hold lasts.
    private var timelineBanked: Duration = .zero
    /// Wall-clock time banked by previous run segments. Never pinned — a hold is
    /// time the person spent breathing.
    private var realBanked: Duration = .zero
    /// `realElapsed` at the moment the current hold began; nil when not holding.
    /// Survives a pause mid-hold, which is what keeps the hold's own timer from
    /// restarting at zero on resume.
    private var holdBegan: Duration?
    private var startedAt: Date?
    private var cueLoop: Task<Void, Never>?
    private var cueRelease: Task<Void, Never>?
    /// Whether the current pause was the app leaving rather than a tap on
    /// Pause. Cleared by any resume, so a hand-paused session never inherits it.
    private var pausedByScene = false

    /// The one initialiser that names the clock; the public way in is in
    /// `SessionModel+Starting.swift`. Internal on purpose — a session outside a
    /// test has exactly one clock to run on, and a suite that has to assert on
    /// where the plan is needs the other. See ``SessionClock``.
    init(
        technique: Technique,
        cues: any SessionCueing,
        recorder: any SessionRecording,
        clock: any SessionClock,
        register: CopyRegister = .plain,
        occasionSlug: OccasionSlug? = nil,
        title: String? = nil,
        warning: SessionWarning? = nil
    ) {
        self.technique = technique
        self.title = title ?? technique.name
        timeline = SessionTimeline(technique: technique, register: register)
        self.warning = warning ?? technique.sessionWarning
        self.cues = cues
        self.recorder = recorder
        self.clock = clock
        self.occasionSlug = occasionSlug
    }

    /// Where the session is in its plan: frozen while paused, frozen while
    /// holding, and clamped at the end.
    public var elapsed: Duration {
        guard status != .holding, let anchor else { return timelineBanked }
        return min(timelineBanked + anchor.duration(to: clock.now), timeline.totalDuration)
    }

    /// How long the person has been in this session, holds and all.
    ///
    /// Diverges from `elapsed` by however much their retentions ran over or
    /// under the typical hold the catalogue seeds. This is the honest number,
    /// and the one the record keeps.
    public var realElapsed: Duration {
        guard let anchor else { return realBanked }
        return realBanked + anchor.duration(to: clock.now)
    }

    /// How long the current hold has run. Zero when there is no hold.
    public var holdElapsed: Duration {
        guard let holdBegan else { return .zero }
        return realElapsed - holdBegan
    }

    /// Whether this session's cues reach the person once the app is away, and
    /// so whether it keeps running when they leave. `pauseForScene()` is the
    /// other reader and the two must agree: iOS grants background runtime for
    /// playing audio only, so a silent session run from out there is suspended
    /// mid-phase, leaving a cue frozen on one breath over a plan that ran on.
    public var followsYouOut: Bool {
        cues.playsInBackground
    }

    /// Whether an open-ended hold is in progress — including while the session
    /// is paused inside one, which is why this reads the hold's own clock rather
    /// than `status`. A paused retention is still a retention.
    public var isInHold: Bool {
        holdBegan != nil
    }

    public func start() {
        guard status == .ready else { return }
        startedAt = .now
        cues.prepare()
        status = .running
        resumeClock()
    }

    public func pause() {
        guard status == .running || status == .holding else { return }
        timelineBanked = elapsed
        realBanked = realElapsed
        anchor = nil
        cueLoop?.cancel()
        cueLoop = nil
        cues.pause()
        status = .paused
    }

    /// Pauses because the app left the screen, remembering that it did — only
    /// this pause undoes itself, and remembering who asked keeps
    /// `resumeIfSceneDriven()` off a hand-paused session. The caller narrows to
    /// `.background`, since iOS sends `.inactive` for a mere banner. Returns
    /// whether a running session stopped; the caller owes a word only then.
    @discardableResult
    public func pauseForScene() -> Bool {
        guard !cues.playsInBackground else { return false }
        guard status == .running || status == .holding else { return false }
        pausedByScene = true
        pause()
        return true
    }

    /// Resumes only a pause `pauseForScene()` caused.
    public func resumeIfSceneDriven() {
        guard pausedByScene else { return }
        resume()
    }

    public func resume() {
        pausedByScene = false
        guard status == .paused else { return }
        // A pause inside a hold resumes into the hold, not past it: the hold's
        // own clock outlives the pause and picks up where it stopped.
        status = isInHold ? .holding : .running
        resumeClock()
    }

    /// Ends an open-ended hold — the "tap when you're ready" affordance.
    ///
    /// The plan resumes at the end of the hold's beat however long the hold
    /// actually took: a short retention does not skip the recovery breath, and a
    /// long one does not eat it.
    public func release() {
        guard status == .holding, let beat = currentBeat, beat.isOpenEnded else { return }

        // Banked before the anchor moves, or the hold's time is measured twice.
        realBanked = realElapsed
        timelineBanked = beat.end
        holdBegan = nil
        status = .running
        resumeClock()
    }

    /// Ends the session where it stands. What was finished is still recorded.
    public func end() {
        guard status == .running || status == .holding || status == .paused else { return }
        finish(completed: false)
    }

    /// Releases the cue hardware now, and is safe to call however many times.
    /// The backstop rather than the route: the view calls this as it goes
    /// away, so `finish` schedules its own release `cueReleaseDelay` out and
    /// this covers the sessions that never reach it.
    public func dismiss() {
        cueLoop?.cancel()
        cueLoop = nil
        cueRelease?.cancel()
        cueRelease = nil
        cues.stop()
    }

    /// The one path back onto the clock, from a start, a resume, or a released
    /// hold — which is why the cues are told here rather than at each of the
    /// three, and why telling them twice on a start has to be harmless.
    private func resumeClock() {
        cues.resume()
        anchor = clock.now
        cueLoop?.cancel()
        cueLoop = Task { await self.runCueLoop() }
    }

    /// Cues the beat the session is actually in, then sleeps until that beat
    /// ends — an absolute instant, recomputed from the timeline each time
    /// round. A phase cue fires on entry only: resuming mid-phase does not
    /// re-fire one, because a half pattern would misdescribe the breath.
    private func runCueLoop() async {
        while !Task.isCancelled {
            guard let beat = timeline.beat(at: elapsed) else {
                finish(completed: true)
                return
            }

            if beat.id != currentBeat?.id {
                currentBeat = beat
                cues.play(beat)
            }

            if beat.isOpenEnded {
                beginHold(at: beat)
                return
            }

            guard let anchor else { return }
            try? await clock.sleep(until: anchor.advanced(by: beat.end - timelineBanked))
        }
    }

    /// Stops the plan at the top of a hold the person ends. Nothing schedules
    /// a wake-up here — that is the whole difference. The plan is pinned to
    /// the hold's start so the phase on screen stays the hold; only the wall
    /// clock keeps running, feeding the hold's timer and the eventual record.
    private func beginHold(at beat: SessionTimeline.Beat) {
        timelineBanked = beat.start
        // Already set when a paused hold resumes; overwriting it would restart
        // the person's hold at zero.
        holdBegan = holdBegan ?? realElapsed
        status = .holding
    }

    private func finish(completed: Bool) {
        cueLoop?.cancel()
        cueLoop = nil

        let elapsed = elapsed
        timelineBanked = elapsed
        realBanked = realElapsed
        anchor = nil
        holdBegan = nil
        status = .finished
        currentBeat = nil

        let record = SessionRecord(
            techniqueSlug: technique.slug,
            startedAt: startedAt ?? .now,
            // Wall-clock, not plan time: an open-ended hold makes the two
            // differ, and what the person did is the one worth keeping.
            duration: realBanked,
            cyclesCompleted: timeline.cyclesCompleted(at: elapsed),
            breathCount: timeline.breathsCompleted(at: elapsed),
            completed: completed,
            occasionSlug: occasionSlug,
            // Stated rather than defaulted: this model *is* the full-screen
            // session, and the discreet sibling states its own.
            surface: .fullScreen
        )
        self.record = record

        if completed {
            cues.playCompletion()

            // The completion cue is playing on hardware this hands back, so the
            // release waits for it — and only for it. Left to `dismiss()` alone
            // it ran when the cover went away, which is after however long
            // somebody spends reading their summary, with an `.playback` audio
            // session ducking the rest of the phone throughout.
            let release = clock.now.advanced(by: Self.cueReleaseDelay)
            cueRelease = Task { [clock, cues] in
                guard await (try? clock.sleep(until: release)) != nil else { return }
                cues.stop()
            }
        } else {
            // A session ended by hand owes silence at once: there is no
            // completion cue to wait out, and a cue that spans its phase — the
            // wrist's pulse train, the phone's swell — is otherwise still playing
            // under the summary.
            cues.stop()
        }

        guard !wasDiscarded else { return }
        Task {
            // Answered before the record is handed over, not after: the
            // recorder is wrapped by `MindfulMinutesRecorder`, whose `record`
            // goes on to ask Health for write access — a system prompt on the
            // very session that earns the first rung. An announcement waiting
            // behind it would land after the screen had been read and left.
            let held = await recorder.recordedSessions().count
            reachedStage = .reached(movingFrom: held, to: held + 1)
            await recorder.record(record)
        }
    }
}

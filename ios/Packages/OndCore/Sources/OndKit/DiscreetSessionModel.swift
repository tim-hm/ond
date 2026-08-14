import Foundation
import Observation

/// Drives one discreet session: `DiscreetCadence`'s bursts over a technique,
/// with nothing between them, and the record left behind.
///
/// A sibling of `SessionModel` rather than a mode of it, because the two share
/// almost none of their hard parts. A discreet session has no pause — pausing
/// a half-hour of mostly silence means nothing — no open-ended holds, and no
/// plan-versus-wall-clock split; what it has instead is gaps measured in
/// minutes, which `SessionModel`'s beat-to-beat cue loop has no vocabulary
/// for. What the two do share is everything around them: `SessionCueing`,
/// `SessionRecording`, `SessionClock`, and the `SessionTimeline` a burst is
/// laid out as.
///
/// The cue loop sleeps to absolute deadlines from one anchor, exactly as
/// `SessionModel`'s does: a wake-up the system delayed must not push every
/// later burst by the same delay, or a late schedule would read as a missing
/// one — on the wrist, the failure the discreet spike exists to measure.
@MainActor
@Observable
public final class DiscreetSessionModel {
    /// Where the session is. Exclusive states, so a view cannot render a
    /// combination that means nothing — there is no pause and no hold here.
    public enum Status: Sendable, Equatable {
        /// Composed but not started; the state a session is in for exactly as
        /// long as it takes the screen to appear and call `start()`.
        case ready
        /// The cadence is underway — bursts and the silences between them.
        case running
        /// Either outcome: the cadence ran out, or the person ended it. The
        /// distinction lives on `record.completed`.
        case finished
    }

    public let technique: Technique
    /// The occasion that prescribed this session, stamped onto the record so
    /// the journey can say which moment the practice served.
    public let occasionSlug: String?

    public private(set) var status: Status = .ready
    public private(set) var record: SessionRecord?

    /// Called once, when the session finishes for either reason — and after a
    /// kept record has been stored, so a handler may sync or report it.
    ///
    /// The seam the workout runtime's release hangs on. Releasing it from the
    /// view's `.onChange` alone is not enough: the normal discreet posture is
    /// wrist down for half an hour, and SwiftUI evaluates no view updates
    /// while the screen is dark — a budget released only by a view callback
    /// stays held until the person next raises their wrist into the app.
    public var onFinished: (@MainActor () -> Void)?

    private let cues: any SessionCueing
    private let recorder: any SessionRecording
    private let clock: any SessionClock
    /// One burst's worth of the technique, reused at every start the cadence
    /// names — the burst is the same six cycles each time it comes around.
    private let burst: SessionTimeline
    private var startedAt: Date?
    private var anchor: ContinuousClock.Instant?
    private var loop: Task<Void, Never>?

    /// The one initialiser that names the clock, internal on `SessionModel`'s
    /// exact terms: outside a test there is only one clock a breath can be
    /// timed against.
    init(
        technique: Technique,
        occasionSlug: String?,
        cues: any SessionCueing,
        recorder: any SessionRecording,
        clock: any SessionClock
    ) {
        self.technique = technique
        self.occasionSlug = occasionSlug
        self.cues = cues
        self.recorder = recorder
        self.clock = clock
        burst = DiscreetCadence.burst(of: technique)
    }

    /// The public way in, on the system clock — the only clock a session
    /// outside a test runs on.
    ///
    /// - Parameters:
    ///   - technique: what a burst is six breaths of.
    ///   - occasionSlug: the occasion that prescribed the session, stamped
    ///     onto the record; nil when the person picked the technique.
    ///   - cues: the wrist's cue controller.
    ///   - recorder: where the finished record goes.
    public convenience init(
        technique: Technique,
        occasionSlug: String?,
        cues: any SessionCueing,
        recorder: any SessionRecording
    ) {
        self.init(
            technique: technique,
            occasionSlug: occasionSlug,
            cues: cues,
            recorder: recorder,
            clock: SystemClock()
        )
    }

    public var totalBursts: Int {
        DiscreetCadence.burstStarts.count
    }

    /// Bursts that have begun, derived from the clock rather than counted by
    /// the loop — the loop and a counter could disagree after a delayed
    /// wake-up, and the clock is the authority the loop itself schedules by.
    ///
    /// Derived from `elapsed`, so a face showing "burst 2 of 5" must read it
    /// on a tick (the model has no stored state to observe for it).
    public var burstsBegun: Int {
        guard status != .ready else { return 0 }
        let elapsed = elapsed
        return DiscreetCadence.burstStarts.count { $0 <= elapsed }
    }

    /// How far into the session the wrist is: one clock, holds and pauses
    /// having no meaning here. Frozen once it finishes — the anchor is gone by
    /// then, and the record's duration is the same number kept.
    public var elapsed: Duration {
        guard let anchor else { return record?.duration ?? .zero }
        return anchor.duration(to: clock.now)
    }

    /// How long the whole cadence runs over this technique.
    public var totalDuration: Duration {
        DiscreetCadence.duration(of: technique)
    }

    /// Whether the ended session was let go rather than kept — the same false
    /// start rule, and the same threshold, as a full-screen session, because
    /// the rule lives on the record both models mint.
    public var wasDiscarded: Bool {
        status == .finished && record?.isFalseStart == true
    }

    /// Starts the cadence. A second call is a no-op — a session is a one-shot
    /// object, composed per tap.
    public func start() {
        guard status == .ready else { return }
        startedAt = .now
        anchor = clock.now
        cues.prepare()
        status = .running
        loop = Task { await run() }
    }

    /// Ends early, by hand — the only control a discreet session offers.
    public func end() {
        guard status == .running else { return }
        finish(completed: false)
    }

    private func run() async {
        guard let anchor else { return }

        for burstStart in DiscreetCadence.burstStarts {
            guard await (try? clock.sleep(until: anchor.advanced(by: burstStart))) != nil else {
                return
            }

            for beat in burst.beats {
                let deadline = anchor.advanced(by: burstStart + beat.start)
                guard await (try? clock.sleep(until: deadline)) != nil else { return }
                cues.play(beat)
            }
        }

        // The last beat's pulse train runs to the end of its phase; finishing under
        // it would end the session by truncating its own final cue. The guard
        // matters as much as the sleep: End lands in this window too, and a
        // swallowed cancellation falling through would finish the session a
        // second time as completed.
        if let lastStart = DiscreetCadence.burstStarts.last, let lastBeat = burst.beats.last {
            let deadline = anchor.advanced(by: lastStart + lastBeat.end)
            guard await (try? clock.sleep(until: deadline)) != nil else { return }
        }

        finish(completed: true)
    }

    private func finish(completed: Bool) {
        // Idempotent by state, not by trust in the callers: `end()` and the
        // loop's own completion can race across the loop's final await, and
        // the second arrival must find nothing left to do — a session that
        // finished twice would record twice under two idempotency keys.
        guard status == .running else { return }

        loop?.cancel()
        loop = nil

        let elapsed = elapsed
        status = .finished

        let (cycles, breaths) = DiscreetCadence.progress(of: technique, at: elapsed)
        let record = SessionRecord(
            techniqueSlug: technique.slug,
            startedAt: startedAt ?? .now,
            duration: elapsed,
            cyclesCompleted: cycles,
            breathCount: breaths,
            completed: completed,
            occasionSlug: occasionSlug,
            surface: .discreet
        )
        // The record before the anchor: `elapsed` falls back to the record's
        // duration, so between the two statements there must be no gap where
        // it reads zero.
        self.record = record
        anchor = nil

        if completed {
            cues.playCompletion()
        }
        cues.stop()

        // The record is stored before anybody is told, and that ordering is the
        // contract `onFinished` carries: the watch's handler syncs the journey
        // and then reports the session to the phone, so a hook that ran first
        // would have the queue read a store the record had not reached — a
        // round trip that uploads nothing, followed by a phone told to come
        // looking for it.
        let kept = !wasDiscarded
        Task {
            if kept {
                await recorder.record(record)
            }
            onFinished?()
        }
    }
}

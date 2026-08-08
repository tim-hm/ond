import Foundation

/// The clock a session is driven by: the instant its two elapsed times are
/// measured from, and the sleep its cue loop waits on.
///
/// A seam for the test suites and nothing else. Every shipping caller gets
/// ``SystemClock``, and `SessionModel`'s public initialiser does not offer the
/// choice, because outside a test there is only one clock a breath can be timed
/// against.
///
/// It exists because a session is scheduled at absolute instants: the cue loop
/// wakes at a beat's end and asks the timeline where the plan now is, so a
/// wake-up later than a beat is long finds the *next* beat and the one in
/// between is never cued. On a phone that is the right answer — a cue for a
/// breath that is already over is worse than no cue at all — but it means a
/// suite driven through real time asserts on whatever the scheduler happened to
/// deliver. With millisecond fixtures on a machine running several builds at
/// once, what it delivered was a skipped stage about one run in eight.
///
/// So a test drives time itself and the plan advances only when it says so,
/// which makes every duration the assertions read an exact one. See
/// `ManualClock` in the test target.
@MainActor
protocol SessionClock {
    var now: ContinuousClock.Instant { get }

    /// Suspends until `deadline`, throwing if the task is cancelled first —
    /// which is how a pause or an ended session stops the cue loop mid-beat.
    func sleep(until deadline: ContinuousClock.Instant) async throws
}

/// The clock every session outside a test runs on.
///
/// `ContinuousClock` rather than `Date` or `SuspendingClock`: a retention that
/// spans the screen locking is still a retention, and time the person spent
/// holding their breath is not something a time-zone change may edit.
struct SystemClock: SessionClock {
    private let clock = ContinuousClock()

    var now: ContinuousClock.Instant {
        clock.now
    }

    func sleep(until deadline: ContinuousClock.Instant) async throws {
        try await clock.sleep(until: deadline)
    }
}

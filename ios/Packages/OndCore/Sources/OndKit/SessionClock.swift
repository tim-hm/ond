import Foundation

/// The clock a session is driven by — a seam for the test suites and nothing
/// else; every shipping caller gets ``SystemClock``. The cue loop wakes at
/// absolute instants, and a late wake skips to the next beat: right on a
/// phone, but it made real-time suites flake, so tests drive time themselves
/// through `ManualClock` in the test target.
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

import Foundation
@testable import OndKit

/// A clock that moves only when a test moves it — `SessionClock` has the why.
/// A cue loop can only wake on an instant a test named, so every duration the
/// assertions read is exact. Advancing past several boundaries in one call
/// gets the honest late-wake answer — beats in between are skipped — so step
/// boundary by boundary when the sequence of cues is the thing under test.
@MainActor
final class ManualClock: SessionClock {
    private(set) var now = ContinuousClock().now

    /// How often a sleeper looks to see whether the test has passed its
    /// deadline. Polling rather than a registered continuation because what is
    /// being waited for is a test's next line, not a wake-up worth scheduling;
    /// this is the only real time in the suite, and nothing measures it.
    private static let pollInterval: Duration = .milliseconds(1)

    /// Moves the session's whole world forward. Any sleeper now past its
    /// deadline wakes on its next poll.
    func advance(by duration: Duration) {
        now = now.advanced(by: duration)
    }

    func sleep(until deadline: ContinuousClock.Instant) async throws {
        while now < deadline {
            try await Task.sleep(for: Self.pollInterval)
        }
    }
}

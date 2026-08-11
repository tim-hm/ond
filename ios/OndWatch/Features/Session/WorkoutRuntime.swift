import Foundation
import HealthKit
import os

/// The runtime budget a discreet session needs, held for as long as it lasts.
///
/// A sibling of `ExtendedRuntime`, not a replacement: the guided session keeps
/// its mindfulness runtime, whose hour is comfortably past any technique in the
/// catalogue. A discreet cadence is different on two counts a
/// `WKExtendedRuntimeSession` cannot answer — it runs close to the half-hour
/// mark with silences over ten minutes long, and it is the session the phone
/// will one day launch remotely, which `startWatchApp` only does into a workout
/// session. `workout-processing` in the target's background modes is what lets
/// `HKWorkoutSession` start at all.
///
/// The contract is `ExtendedRuntime`'s exactly: nothing observable, nothing to
/// handle. No health store, a withheld grant, a session refused because a real
/// workout is already recording — all land in the same place. The budget is
/// missing, the log says so, and the cadence carries on without it; a person
/// mid-silence is worth more than a tidy invariant.
///
/// No workout builder is ever attached, so ending the session leaves nothing in
/// Health: mindful minutes stay the app's only write, and no "Mind & Body
/// workout" appears beside a breathing practice.
@MainActor
final class WorkoutRuntime: NSObject {
    private nonisolated static let logger = Logger(category: "workout-runtime")

    private let health = HKHealthStore()
    private var session: HKWorkoutSession?
    /// The start in flight, held so `invalidate()` can cancel a budget still
    /// being asked for — the authorization sheet can outlast the session that
    /// wanted it.
    private var starting: Task<Void, Never>?

    /// Asks for the budget. A second call while one is running or starting is
    /// a no-op — the system refuses overlapping workout sessions.
    func start() {
        guard session == nil, starting == nil else { return }
        starting = Task {
            await begin()
            // Only the task still holding the handle may clear it: a
            // cancelled predecessor resuming here after an invalidate/start
            // cycle must not erase its successor's, or the successor becomes
            // uncancellable and starts a workout nothing ends.
            if !Task.isCancelled {
                starting = nil
            }
        }
    }

    /// Hands the budget back. Called as the session's screen goes away, so a
    /// finished cadence does not keep a workout open while somebody reads a
    /// summary.
    func invalidate() {
        starting?.cancel()
        starting = nil
        session?.end()
        session = nil
    }

    private func begin() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            Self.logger.notice("no health store — the cadence runs with no runtime")
            return
        }

        // Starting a workout session requires the share grant for the workout
        // type even though this one never saves anything. The system shows its
        // sheet once; every later call is a cheap round trip to the daemon.
        try? await health.requestAuthorization(toShare: [.workoutType()], read: [])
        guard !Task.isCancelled else { return }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .mindAndBody

        do {
            let session = try HKWorkoutSession(
                healthStore: health,
                configuration: configuration
            )
            session.delegate = self
            self.session = session
            session.startActivity(with: Date())
        } catch {
            Self.logger.notice(
                "the workout session was refused: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}

/// HealthKit calls these on its own queue and the protocol carries no
/// isolation, so the one that touches state hops explicitly — the same dance
/// `ExtendedRuntime` does with WatchKit.
extension WorkoutRuntime: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from _: HKWorkoutSessionState,
        date _: Date
    ) {
        Self.logger.notice("the workout session moved to state \(toState.rawValue)")
    }

    nonisolated func workoutSession(
        _: HKWorkoutSession,
        didFailWithError error: any Error
    ) {
        // Nothing to do but say so: ending the cadence here would stop
        // somebody's session because the runtime around it went away.
        Self.logger.notice(
            "the workout session failed: \(error.localizedDescription, privacy: .public)"
        )
        Task { @MainActor in self.session = nil }
    }
}

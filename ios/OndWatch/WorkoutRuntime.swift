import Foundation
import HealthKit
import os

/// The runtime budget a discreet session needs. `ExtendedRuntime`'s sibling:
/// a `WKExtendedRuntimeSession` covers neither ten-minute silences nor a
/// remote launch, which `startWatchApp` only does into a workout session.
/// `workout-processing` (background modes) lets it start; every failure just
/// logs and the cadence carries on; no builder attached, nothing written to Health.
@MainActor
final class WorkoutRuntime: NSObject {
    /// The one budget: the system grants one workout session per process, and
    /// three unrelated places need the same one — the launch handler, the
    /// session screens, and the order model that declines an order while it
    /// is held. Passing one instance through them made "every call site got
    /// the same object" an invariant asserted nowhere, broken silently.
    static let shared = WorkoutRuntime()

    private nonisolated static let logger = Logger(category: "session-runtime")

    /// How long a budget nobody has claimed is held before it is handed back.
    /// A phone-launched app takes it before it knows what for, and ordinary
    /// outcomes leave no claimant; left held, the workout drains the battery,
    /// shows on the face, and blocks the next real one. Generous enough to
    /// cover the cold catalogue fetch the scene is doing meanwhile.
    private static let unclaimed: Duration = .seconds(30)

    /// The hand-back armed by `startUnclaimed()`, cancelled the moment a session
    /// claims the budget — which is `start()`, so no caller has to remember to.
    private var handBack: Task<Void, Never>?

    /// Lazy because the app now builds this at launch — the delegate has to hold
    /// one before any screen exists to claim it — and creating an `HKHealthStore`
    /// opens a connection to the health daemon that most launches never use.
    /// `HealthKitHealthStore.store` is lazy for the same reason.
    private lazy var health = HKHealthStore()
    private var session: HKWorkoutSession?
    /// The start in flight, held so `invalidate()` can cancel a budget still
    /// being asked for — the authorization sheet can outlast the session that
    /// wanted it.
    private var starting: Task<Void, Never>?

    /// Whether a **session** holds the budget, not a launch holding it open —
    /// the honest "is this wrist mid-cadence"; `WristOrderModel` declines on
    /// it. Asked merely whether a workout runs, this wrist refused every
    /// order: the launch takes the budget first, so each order found one
    /// "already running". A pending hand-back means unclaimed; `start()` cancels it.
    var isClaimed: Bool {
        (session != nil || starting != nil) && handBack == nil
    }

    /// Takes the budget for a launch that has nothing to spend it on yet, and
    /// hands it back if nothing claims it — the phone-launched path, where the
    /// system requires a workout to start promptly and the order explaining why
    /// arrives a beat later.
    func startUnclaimed() {
        // A launch that arrives over a running session takes nothing and, above
        // all, arms nothing: the hand-back below would end a workout somebody's
        // cadence is already living on, thirty seconds into a silence, and the
        // taps would stop when the app was next suspended.
        guard !isClaimed else {
            Self.logger.notice("a session already holds the workout; the launch takes nothing")
            return
        }

        // `start()` has just cleared any pending hand-back, so this arms the one
        // and only timer standing over an unclaimed budget.
        start()

        handBack = Task {
            try? await Task.sleep(for: Self.unclaimed)
            guard !Task.isCancelled else { return }
            Self.logger.notice("no session claimed the launched workout; handing it back")
            invalidate()
        }
    }

    /// Asks for the budget, and claims it: a session calling this is the owner
    /// `startUnclaimed()` was waiting for, so the hand-back stands down. A second
    /// call while one is running or starting is a no-op — the system refuses
    /// overlapping workout sessions.
    func start() {
        handBack?.cancel()
        handBack = nil

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
        handBack?.cancel()
        handBack = nil
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

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
    /// The one budget, because the system grants one workout session per process
    /// and three unrelated places now need the same one: the launch handler,
    /// which takes it before any screen exists; the session screens, which take
    /// it when they appear; and the order model, which declines an order while it
    /// is held. Passing one instance through all of them was the alternative, and
    /// it made the invariant "every call site was handed the same object" —
    /// asserted nowhere, broken silently.
    static let shared = WorkoutRuntime()

    private nonisolated static let logger = Logger(category: "workout-runtime")

    /// How long a budget nobody has claimed is held before it is handed back.
    ///
    /// A phone-launched app takes the budget before it knows what for, and
    /// several ordinary outcomes mean no session ever claims it: a technique this
    /// build does not hold, a context the phone withdrew first, an order the
    /// ledger refuses as already run. Left held, the workout keeps the app alive,
    /// drains the battery, shows a workout on the face that nobody is doing, and
    /// blocks the next real one the person starts elsewhere. Generous enough to
    /// cover a cold catalogue fetch, which is what the scene is doing meanwhile.
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

    /// Whether a **session** holds the budget, as opposed to a launch holding it
    /// open for one that has not arrived yet — which is the honest answer to "is
    /// this wrist mid-cadence", since every cadence long enough to need a budget
    /// takes one. `WristOrderModel` declines an order on it.
    ///
    /// The distinction is the whole point and it is not decoration: asked merely
    /// whether a workout is running, this wrist refused every order the phone
    /// ever sent it. `handle(_:)` takes the budget before any screen exists, so a
    /// beat later the order that caused the launch arrived, found a workout
    /// running, and was declined as "already mid-session" — the watch app opened
    /// and sat on its menu while the phone reported that nothing had answered.
    ///
    /// The pending hand-back is the tell. It is armed only while nothing owns the
    /// budget, and `start()` — which is what a session's screen calls — cancels
    /// it. So a workout with a hand-back still pending is one that is looking for
    /// its session, and a workout without one has found it.
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

        start()

        handBack?.cancel()
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

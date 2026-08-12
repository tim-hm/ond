#if canImport(HealthKit) && os(iOS)
    import Foundation
    import HealthKit
    import os
    import WatchConnectivity

    /// Launches the paired watch's app into a workout session.
    ///
    /// The phone's counterpart to the wrist's `WorkoutRuntime`, and separate from
    /// `HealthKitHealthStore` for the reason that type's doc draws: this holds
    /// HealthKit for the *runtime* and never reads or writes a sample. Keeping
    /// the two apart is what lets the sole-reader-of-Health-data claim stay a
    /// fact rather than an aspiration.
    ///
    /// An actor because `HKHealthStore` is not `Sendable` and `WristLaunching`
    /// is: isolation is what lets this hold the store without an unchecked
    /// conformance.
    public actor WristLauncher: WristLaunching {
        private static let logger = Logger(category: "watch-link")

        /// Lazy on `HealthKitHealthStore`'s reasoning: the composition root
        /// builds this during launch, creating the store opens a connection to
        /// the health daemon, and most launches never hand anything to a wrist.
        private lazy var store = HKHealthStore()

        public init() {}

        public func launchWatchApp() async -> Bool {
            guard HKHealthStore.isHealthDataAvailable() else { return false }
            // A wrist to launch, established before a grant to launch it with.
            // `startWatchApp` fails on an unpaired phone whatever it holds, and
            // asking first would put a Health sheet in front of somebody who owns
            // no watch — which for a session quietly looking for a pulse is a
            // sheet nobody asked for at all.
            guard WCSession.isSupported(), WCSession.default.isPaired else { return false }

            // The same configuration the wrist's own runtime uses: the system
            // requires one to launch into, and mindAndBody is the only kind of
            // session this app ever is.
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .mindAndBody

            // The grant first, and it is the phone's own: `startWatchApp` starts
            // a workout session on the wrist, and iOS refuses to ask for one
            // unless this app may share workout data — even though neither
            // device ever saves a workout. Without this the launch fails on
            // every fresh install with nothing anywhere prompting for it, and
            // the feature reads as a watch that never answers.
            guard await grant() else { return false }

            return await withCheckedContinuation { continuation in
                store.startWatchApp(with: configuration) { launched, error in
                    if let error {
                        Self.logger.notice(
                            "the watch app launch was refused: \(error.localizedDescription, privacy: .public)"
                        )
                    }
                    continuation.resume(returning: launched)
                }
            }
        }

        /// Asks for the workout share grant, once per process.
        ///
        /// - Returns: whether asking was even possible. A refusal is
        ///   indistinguishable from a grant here — HealthKit does not say — so a
        ///   declined person falls through to the launch, which fails, which is
        ///   the sheet's "start it from OndWatch" and the truthful outcome.
        private func grant() async -> Bool {
            guard !hasRequested else { return true }
            hasRequested = true
            do {
                try await store.requestAuthorization(toShare: [.workoutType()], read: [])
                return true
            } catch {
                Self.logger.notice(
                    "the workout grant could not be asked for: \(error.localizedDescription, privacy: .public)"
                )
                return false
            }
        }

        /// Whether this process has already shown the sheet. The system shows it
        /// at most once per install, but every repeat ask is still a round trip
        /// to the daemon, and this sits in front of a tap somebody is waiting on.
        private var hasRequested = false
    }
#endif

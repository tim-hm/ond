#if canImport(HealthKit) && os(iOS)
    import Foundation
    import HealthKit
    import os
    import WatchConnectivity

    /// Launches the paired watch's app into a workout session. Separate from
    /// `HealthKitHealthStore`: this holds HealthKit for the runtime and never
    /// reads or writes a sample, which keeps the sole-reader-of-Health-data
    /// claim a fact. An actor because `HKHealthStore` is not `Sendable` and
    /// `WristLaunching` is — isolation avoids an unchecked conformance.
    public actor WristLauncher: WristLaunching {
        private static let logger = Logger(category: "watch-link")

        /// Lazy on `HealthKitHealthStore`'s reasoning: the composition root
        /// builds this during launch, creating the store opens a connection to
        /// the health daemon, and most launches never hand anything to a wrist.
        private lazy var store = HKHealthStore()

        public init() {}

        public func prepare() async {
            guard HKHealthStore.isHealthDataAvailable(), mayHaveAWrist else { return }
            _ = await grant()
        }

        public func launchWatchApp() async -> Bool {
            guard HKHealthStore.isHealthDataAvailable(), mayHaveAWrist else { return false }

            // The same configuration the wrist's own runtime uses: the system
            // requires one to launch into, and mindAndBody is the only kind of
            // session this app ever is.
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .mindAndBody

            // The grant first, and it is the phone's own: iOS refuses
            // `startWatchApp` unless this app may share workout data, even
            // though neither device ever saves a workout. Without it the
            // launch fails on every fresh install with nothing prompting.
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
        /// - Returns: whether asking was even possible. HealthKit does not
        ///   reveal a refusal, so a declined person falls through to the
        ///   launch, which fails — the truthful outcome.
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

        /// Whether there is a wrist worth asking about: requesting the grant
        /// first would put a Health sheet in front of somebody who owns no
        /// watch. An unactivated session counts as "maybe" — `isPaired` is
        /// meaningless before activation, and reading it as unpaired would
        /// silently lose a real launch in the seconds after a cold start.
        private var mayHaveAWrist: Bool {
            guard WCSession.isSupported() else { return false }

            let session = WCSession.default
            return session.activationState != .activated || session.isPaired
        }
    }
#endif

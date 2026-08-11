#if canImport(HealthKit)
    import Foundation
    import HealthKit
    import os

    /// The only type in the repository that reads or writes Health *data*
    /// through `HealthKit`. Every other importer holds it for a workout-session
    /// *runtime* and never touches a sample: `WristLauncher` on the phone, the
    /// wrist's `WorkoutRuntime` and the `WatchAppDelegate` that owns one, and
    /// the DEBUG-only `DiscreetSpike`.
    ///
    /// Everything above it works in `DailyQuantity` values, which is what lets the
    /// summary thresholds be tested on the host with no paired watch and no Health
    /// data. The whole file sits behind `canImport(HealthKit)` because HealthKit
    /// does not exist on macOS, and the host is where `mise run test:swift` runs.
    ///
    /// An actor only because `HKHealthStore` is not `Sendable` and the seam is:
    /// isolation is what lets this hold the store without an unchecked conformance.
    /// Every failure — no Health store on this device, access not granted, a query
    /// erroring — answers empty or returns quietly, which is the seam's contract:
    /// Health is an enhancement, never an error surface — except the mindful-session
    /// write, where "never attempted" and "refused" are otherwise the same silence.
    public actor HealthKitHealthStore: HealthStore {
        private static let logger = Logger(category: "health")

        /// Lazy because both composition roots build this during app launch:
        /// creating an `HKHealthStore` opens the connection to the health
        /// daemon, and nothing touches Health until a session ends — if ever.
        private lazy var store = HKHealthStore()

        /// Whether this process has already asked for the write grant. The
        /// system shows its sheet at most once per install, but every repeat
        /// request is still a round trip to the daemon — and the recorder asks
        /// on every finished session.
        private var hasRequestedWriteAuthorization = false

        /// Whether a refused write has already been logged this launch.
        ///
        /// A withheld grant refuses every session's write for as long as it
        /// stands, and the recorder attempts one after every session — so
        /// without this the standing state costs a persisted line a day for as
        /// long as somebody practises, evicting the sync and identity failures
        /// the log store is kept for. The first refusal says everything the
        /// later ones would.
        private var hasLoggedWriteRefusal = false

        public init() {}

        public func requestReadAuthorization() async {
            guard HKHealthStore.isHealthDataAvailable() else { return }
            try? await store.requestAuthorization(
                toShare: [],
                read: [
                    HKQuantityType(.respiratoryRate),
                    HKQuantityType(.restingHeartRate),
                    HKQuantityType(.heartRateVariabilitySDNN),
                ]
            )
        }

        public func requestWriteAuthorization() async {
            guard HKHealthStore.isHealthDataAvailable(), !hasRequestedWriteAuthorization else {
                return
            }
            // Set before the await, so a second caller arriving through actor
            // re-entrancy does not start a duplicate request.
            hasRequestedWriteAuthorization = true
            try? await store.requestAuthorization(
                toShare: [HKCategoryType(.mindfulSession)],
                read: []
            )
        }

        /// The same unit as resting heart rate — counts per minute — measuring
        /// a different thing. HealthKit has no separate breath unit, so the two
        /// queries are told apart by their sample type and by nothing else.
        public func respiratoryRate(from start: Date, to end: Date) async -> [DailyQuantity] {
            await dailyAverage(
                of: HKQuantityType(.respiratoryRate),
                in: HKUnit.count().unitDivided(by: .minute()),
                from: start,
                to: end
            )
        }

        public func restingHeartRate(from start: Date, to end: Date) async -> [DailyQuantity] {
            await dailyAverage(
                of: HKQuantityType(.restingHeartRate),
                in: HKUnit.count().unitDivided(by: .minute()),
                from: start,
                to: end
            )
        }

        public func heartRateVariability(from start: Date, to end: Date) async -> [DailyQuantity] {
            await dailyAverage(
                of: HKQuantityType(.heartRateVariabilitySDNN),
                in: .secondUnit(with: .milli),
                from: start,
                to: end
            )
        }

        public func writeMindfulSession(from start: Date, to end: Date) async {
            guard HKHealthStore.isHealthDataAvailable(), end > start else { return }
            let sample = HKCategorySample(
                type: HKCategoryType(.mindfulSession),
                value: HKCategoryValue.notApplicable.rawValue,
                start: start,
                end: end
            )
            do {
                try await store.save(sample)
            } catch {
                guard !hasLoggedWriteRefusal else { return }
                hasLoggedWriteRefusal = true
                Self.logger.notice(
                    "failed to write the mindful session: \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        /// One day-bucketed average query, shared by both metrics.
        ///
        /// `discreteAverage` over day buckets is what turns however many readings a
        /// day holds into the one `DailyQuantity` the summary builder expects.
        /// Days with no readings produce no statistics and therefore no entry —
        /// the series is sparse rather than zero-filled, which is what keeps "no
        /// data" distinct from "a reading of zero" all the way up.
        private func dailyAverage(
            of type: HKQuantityType,
            in unit: HKUnit,
            from start: Date,
            to end: Date
        ) async -> [DailyQuantity] {
            guard HKHealthStore.isHealthDataAvailable() else { return [] }

            let descriptor = HKStatisticsCollectionQueryDescriptor(
                predicate: HKSamplePredicate.quantitySample(
                    type: type,
                    predicate: HKQuery.predicateForSamples(withStart: start, end: end)
                ),
                options: .discreteAverage,
                // Anchored to the local midnight before the window, so every
                // bucket is a calendar day rather than a 24-hour offset of the
                // moment somebody asked.
                anchorDate: Calendar.current.startOfDay(for: start),
                intervalComponents: DateComponents(day: 1)
            )
            guard let collection = try? await descriptor.result(for: store) else { return [] }

            return collection.statistics()
                .compactMap { statistics in
                    statistics.averageQuantity().map {
                        DailyQuantity(day: statistics.startDate, value: $0.doubleValue(for: unit))
                    }
                }
                .sorted { $0.day < $1.day }
        }
    }

#endif

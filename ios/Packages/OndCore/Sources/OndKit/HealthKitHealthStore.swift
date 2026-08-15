#if canImport(HealthKit)
    import Foundation
    import HealthKit
    import os

    /// The only type in the repository that reads or writes Health *data*
    /// through `HealthKit`. Every other importer holds it for a workout-session
    /// *runtime* and never touches a sample: `WristLauncher` on the phone, plus
    /// the wrist's `WorkoutRuntime` and the `WatchAppDelegate` that owns one.
    ///
    /// Everything above it works in `DailyQuantity` values, which is what lets the
    /// summary thresholds be tested on the host with no paired watch and no Health
    /// data. The whole file sits behind `canImport(HealthKit)` so portable hosts
    /// can still build OndKit; the value and failure rules stay outside it so
    /// `mise run test:swift` exercises them without a populated Health store.
    ///
    /// An actor only because `HKHealthStore` is not `Sendable` and the seam is:
    /// isolation is what lets this hold the store without an unchecked conformance.
    /// Every failure — no Health store on this device, access not granted, a query
    /// erroring — answers empty or returns quietly, which is the seam's contract:
    /// Health is an enhancement, never an error surface — except the writes, where
    /// "never attempted" and "refused" are otherwise the same silence.
    public actor HealthKitHealthStore: HealthStore, PulseSource {
        private static let logger = Logger(category: "health")
        private static let reads = HealthKitReadBoundary()

        /// Lazy because both composition roots build this during app launch:
        /// creating an `HKHealthStore` opens the connection to the health
        /// daemon, and nothing touches Health until a session ends — if ever.
        private lazy var store = HKHealthStore()

        /// Which sample types this process has already asked to share. The
        /// system shows its sheet at most once per install, but every repeat
        /// request is still a round trip to the daemon — and a session attempts
        /// both writes every time.
        private var requestedGrants: Set<HKSampleType> = []

        /// Which sample types this process has already asked to read. Separate
        /// from the shares above rather than one set for both: the two grants are
        /// separate in HealthKit, and a type this app both read and wrote would
        /// otherwise have one ask stand in for the other.
        private var requestedReads: Set<HKSampleType> = []

        /// Which writes have already been logged as refused this launch.
        ///
        /// A withheld grant refuses its write for as long as it stands, and a
        /// session attempts every one of them — so without this the standing
        /// state costs a persisted line a day for as long as somebody
        /// practises, evicting the sync and identity failures the log store is
        /// kept for. The first refusal says everything the later ones would.
        ///
        /// Keyed by sample type rather than one flag for all of them: the
        /// grants are separate, so a refused State of Mind must not silence the
        /// first report that Mindful Minutes are going nowhere either.
        private var loggedRefusals: Set<HKSampleType> = []

        public init() {}

        public func requestReadAuthorization() async {
            guard HKHealthStore.isHealthDataAvailable() else { return }
            let types: Set<HKObjectType> = [
                HKQuantityType(.respiratoryRate),
                HKQuantityType(.restingHeartRate),
                HKQuantityType(.heartRateVariabilitySDNN),
            ]
            _ = await Self.reads.perform(
                .authorization,
                sampleTypes: types.map(\.identifier).sorted()
            ) {
                try await store.requestAuthorization(toShare: [], read: types)
            }
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

        public func readings() async -> AsyncStream<HeartRateSample> {
            AsyncStream { continuation in
                let readings = Task { await self.stream(into: continuation) }
                // Dropping the stream stops the query: the task's cancellation
                // ends the `for await` below, and HealthKit tears its own query
                // down with the sequence. Nothing here holds the query itself —
                // it belongs to the actor for its whole life.
                continuation.onTermination = { _ in readings.cancel() }
            }
        }

        /// Through the same `requestedGrants` gate `save` uses, so this and the
        /// first write cannot produce two sheets whichever of them runs first —
        /// and so skipping this costs the write nothing but its own ask.
        public func requestMindfulWriteAuthorization() async {
            guard HKHealthStore.isHealthDataAvailable() else { return }

            let type = HKCategoryType(.mindfulSession)
            guard requestedGrants.insert(type).inserted else { return }

            try? await store.requestAuthorization(toShare: [type], read: [])
        }

        public func writeMindfulSession(from start: Date, to end: Date) async {
            guard end > start else { return }
            await save(
                HKCategorySample(
                    type: HKCategoryType(.mindfulSession),
                    value: HKCategoryValue.notApplicable.rawValue,
                    start: start,
                    end: end
                ),
                describedAs: "the mindful session"
            )
        }

        /// A momentary emotion rather than a daily mood: this is how somebody
        /// feels at the moment they were asked, twice around one practice, and
        /// a day's mood is a different claim that would overwrite itself.
        ///
        /// Associated with self-care, which is what the Health app groups it
        /// under, and carrying no emotion label. A tap on a pleasantness scale
        /// says how somebody feels, not *what* they feel — naming an emotion
        /// they did not choose would be this app putting a word in their mouth.
        public func writeMood(_ mood: Mood, at date: Date) async {
            await save(
                HKStateOfMind(
                    date: date,
                    kind: .momentaryEmotion,
                    valence: mood.valence,
                    labels: [],
                    associations: [.selfCare]
                ),
                describedAs: "the state of mind"
            )
        }

        /// Asks for `sample`'s grant if this process has not yet, then saves it,
        /// reporting a standing refusal exactly once — see `loggedRefusals`.
        ///
        /// The grant is the sample's own business rather than a call its caller
        /// has to remember, which is the whole of `HealthStore`'s write
        /// contract. `what` is prose for the log line and nothing more; both the
        /// grant and the refusal dedupe key come off the sample itself, so
        /// rewording a log line cannot silently re-arm either.
        private func save(_ sample: HKSample, describedAs what: String) async {
            guard HKHealthStore.isHealthDataAvailable() else { return }

            let type = sample.sampleType
            // Inserted before the await, so a second caller arriving through
            // actor re-entrancy does not start a duplicate request.
            if requestedGrants.insert(type).inserted {
                // The save below is the write boundary and reports this refusal
                // once; reporting the grant too would make one failed write two.
                try? await store.requestAuthorization(toShare: [type], read: [])
            }

            do {
                try await store.save(sample)
            } catch {
                guard loggedRefusals.insert(type).inserted else { return }
                Self.logger.notice(
                    "failed to write \(what, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        /// Feeds `heartRate()`'s stream until whoever asked for it lets go.
        ///
        /// An anchored query rather than a workout builder's collected samples,
        /// which is the other way to watch a heart rate on the wrist and the one
        /// that would end with a workout saved in Health. This reads what the
        /// sensor is already writing and adds nothing to it — no workout of this
        /// app's is ever saved, on either device.
        ///
        /// Anchored at the moment of asking, so the first thing a session sees is
        /// the wearer's heart now rather than a backlog of this morning's.
        private func stream(into continuation: AsyncStream<HeartRateSample>.Continuation) async {
            defer { continuation.finish() }
            guard HKHealthStore.isHealthDataAvailable() else { return }

            let type = HKQuantityType(.heartRate)
            // Asked once per process, on the shares' reasoning above: the sheet
            // shows at most once per install, but a repeat ask is still a round
            // trip to the daemon — and this one sits in front of the first
            // reading somebody is waiting for.
            if requestedReads.insert(type).inserted {
                _ = await Self.reads.perform(
                    .authorization,
                    sampleTypes: [type.identifier]
                ) {
                    try await store.requestAuthorization(toShare: [], read: [type])
                }
            }
            guard !Task.isCancelled else { return }

            let unit = HKUnit.count().unitDivided(by: .minute())
            let descriptor = HKAnchoredObjectQueryDescriptor(
                predicates: [
                    .quantitySample(
                        type: type,
                        predicate: HKQuery.predicateForSamples(withStart: Date(), end: nil)
                    ),
                ],
                anchor: nil
            )

            _ = await Self.reads.perform(.query, sampleTypes: [type.identifier]) {
                for try await batch in descriptor.results(for: store) {
                    for sample in batch.addedSamples {
                        continuation.yield(
                            HeartRateSample(
                                date: sample.endDate,
                                beatsPerMinute: sample.quantity.doubleValue(for: unit)
                            )
                        )
                    }
                }
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

            guard let collection = await Self.reads.perform(
                .query,
                sampleTypes: [type.identifier],
                body: {
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
                    return try await descriptor.result(for: store)
                }
            ) else { return [] }

            return collection.statistics()
                .compactMap { statistics in
                    guard let average = statistics.averageQuantity() else { return nil }
                    return DailyQuantity(
                        day: statistics.startDate,
                        value: average.doubleValue(for: unit)
                    )
                }
                .sorted { $0.day < $1.day }
        }
    }

#endif

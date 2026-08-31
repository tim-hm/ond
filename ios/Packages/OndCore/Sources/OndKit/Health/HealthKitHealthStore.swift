#if canImport(HealthKit)
    import Foundation
    import HealthKit
    import os

    /// The only type in the repository that reads or writes Health *data*
    /// through `HealthKit`; other importers hold it only for a workout runtime.
    /// Everything above works in `DailyQuantity`, host-testable with no watch.
    /// An actor only because `HKHealthStore` is not `Sendable`. Every failure
    /// answers empty or returns quietly — except writes, which log a refusal.
    public actor HealthKitHealthStore: HealthStore, PulseSource {
        private static let logger = Logger(category: "health")
        private static let reads = HealthKitReadBoundary()

        /// Lazy because both composition roots build this during app launch:
        /// creating an `HKHealthStore` opens the connection to the health
        /// daemon, and nothing touches Health until a session starts — if ever.
        /// The first touch is `writeMoodMayPrompt()`, asked once a launch by
        /// a session that offers the mood check.
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

        /// Which writes have already been logged as refused this launch. A
        /// standing refusal recurs every session, and a persisted line a day
        /// would evict the sync and identity failures the log store is kept
        /// for — the first refusal says everything. Keyed by sample type: a
        /// refused State of Mind must not silence Mindful Minutes' report.
        private var loggedRefusals: Set<HKSampleType> = []

        public init() {}

        public func requestReadAuthorization() async {
            guard HKHealthStore.isHealthDataAvailable() else { return }
            // Heart rate rides the same sheet as the three trend types rather
            // than asking again later: one switch grants the read, and a second
            // system prompt appearing the first time Home draws a card would be
            // a question nobody connected to the switch they already answered.
            let types: Set<HKObjectType> = [
                HKQuantityType(.respiratoryRate),
                HKQuantityType(.restingHeartRate),
                HKQuantityType(.heartRateVariabilitySDNN),
                HKQuantityType(.heartRate),
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
                in: Self.beatsPerMinute,
                from: start,
                to: end
            )
        }

        public func restingHeartRate(from start: Date, to end: Date) async -> [DailyQuantity] {
            await dailyAverage(
                of: HKQuantityType(.restingHeartRate),
                in: Self.beatsPerMinute,
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

        /// Beats a minute, which resting heart rate and the live stream also
        /// measure in — one spelling, so three queries cannot disagree about
        /// what they are converting to.
        private static let beatsPerMinute = HKUnit.count().unitDivided(by: .minute())

        /// One bounded query per window, run in sequence. Sequential rather
        /// than a `TaskGroup`: this actor's isolation serialises `Self.reads`,
        /// and a group's child tasks are not isolated to it. Ten windows at
        /// most, behind a model that will not re-read inside a minute.
        public func averageHeartRate(inEachOf windows: [DateInterval]) async -> [WindowedQuantity] {
            guard HKHealthStore.isHealthDataAvailable(), !windows.isEmpty else { return [] }

            let type = HKQuantityType(.heartRate)
            var readings: [WindowedQuantity] = []

            for window in windows {
                // Cancellation ends the read rather than turning the rest of the
                // windows into silences: the boundary swallows a cancelled query
                // into the same nil an empty window produces, and the caller
                // cannot tell those apart. It checks `Task.isCancelled` itself
                // before committing anything; this only stops the queries.
                guard !Task.isCancelled else { break }

                let average = await Self.reads.perform(
                    .query,
                    sampleTypes: [type.identifier],
                    body: {
                        let descriptor = HKStatisticsQueryDescriptor(
                            predicate: HKSamplePredicate.quantitySample(
                                type: type,
                                predicate: HKQuery.predicateForSamples(
                                    withStart: window.start,
                                    end: window.end
                                )
                            ),
                            options: .discreteAverage
                        )
                        return try await descriptor.result(for: store)?.averageQuantity()
                    }
                )

                // Two nils collapse to one silence here: the boundary's own
                // failure, and a window Health simply had nothing in. Neither is
                // an entry, and the caller reads both as "no reading" — which is
                // the truth for a session breathed without a watch on.
                guard let average = average.flatMap(\.self),
                      let reading = WindowedQuantity(
                          window: window,
                          value: average.doubleValue(for: Self.beatsPerMinute)
                      )
                else { continue }

                readings.append(reading)
            }

            return readings
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

        /// A momentary emotion rather than a daily mood: how somebody feels at
        /// the moment they were asked, twice around one practice. Associated
        /// with self-care and carrying no emotion label — a tap on a
        /// pleasantness scale says how somebody feels, not *what*; naming an
        /// emotion they did not choose would put a word in their mouth.
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

        /// Undecided is the only state that shows a sheet: a granted or a
        /// refused write goes through without one. `notDetermined` is also the
        /// answer where Health is unavailable, so that case is answered first.
        public func writeMoodMayPrompt() async -> Bool {
            guard HKHealthStore.isHealthDataAvailable() else { return false }

            return store.authorizationStatus(for: HKObjectType.stateOfMindType())
                == .notDetermined
        }

        /// Asks for `sample`'s grant if this process has not yet, then saves
        /// it, reporting a standing refusal exactly once — see
        /// `loggedRefusals`. Both the grant and the dedupe key come off the
        /// sample itself, so rewording the log line (`what`) cannot re-arm
        /// either.
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

        /// Feeds `heartRate()`'s stream until whoever asked for it lets go. An
        /// anchored query rather than a workout builder's samples: this reads
        /// what the sensor is already writing, and no workout of this app's is
        /// ever saved, on either device. Anchored at the moment of asking, so
        /// a session sees the heart now rather than a backlog of the morning's.
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
                                beatsPerMinute: sample.quantity
                                    .doubleValue(for: Self.beatsPerMinute)
                            )
                        )
                    }
                }
            }
        }

        /// One day-bucketed average query, shared by both metrics. Days with
        /// no readings produce no entry — the series is sparse rather than
        /// zero-filled, which keeps "no data" distinct from "a reading of
        /// zero" all the way up.
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
                        // The caller's unit, not `beatsPerMinute`: HRV comes
                        // through here in milliseconds, and converting it as a
                        // rate throws NSInvalidArgumentException on the first
                        // device with a real sample. The simulator never has
                        // one, so only a phone can catch this line being wrong.
                        value: average.doubleValue(for: unit)
                    )
                }
                .sorted { $0.day < $1.day }
        }
    }

#endif

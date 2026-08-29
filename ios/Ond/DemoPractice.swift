#if DEBUG
    import Foundation
    import OndKit

    /// A fixed practice history, installed when `--ui-testing-demo` is passed:
    /// the App Store screenshots need Home, Progress and the journal populated.
    /// Debug and argument-gated, both — Release never compiles this, and the
    /// argument keeps it out of the other UI tests. Dates derive from today so
    /// the fixture never goes stale; `@MainActor` isolates the mutable guard.
    @MainActor
    enum DemoPractice {
        /// How far back the history runs.
        ///
        /// Six weeks is chosen against the journal rather than Home: it is long
        /// enough that `hasEarlierSessions` is true and the "show earlier" affordance
        /// appears in shot, which a fortnight would not do.
        private static let span = 42

        /// Days at the end with no gap in them.
        ///
        /// The gaps below are kept strictly outside this window, because a streak
        /// is counted back from today and one missed day inside it would show a
        /// number that contradicts the journal directly above it.
        private static let streak = 12

        /// The techniques practised, read from the bundled catalogue rather
        /// than listed as slugs: a literal list keeps a dead slug through a
        /// seed rename and renders a blank journal row into a screenshot with
        /// nothing failing. The `OndKit` export resolves with no server running.
        private static let techniques = CatalogueExport.bundled.techniques

        /// The one installation this process will do; later callers join it.
        /// The launch task runs per appearance of the root view — seven times
        /// in a measured run — and deterministic ids would converge anyway, so
        /// this only stops the redundant erase-and-rewrite passes. Assigned
        /// before the first await, so later callers wait rather than start.
        private static var installation: Task<Void, Never>?

        /// Installs the fixture if this launch asked, and reports whether it
        /// did so the caller skips `journey.sync()` — the sync would upload six
        /// weeks of invented practice. Skipping it is not sufficient: another
        /// drain still uploads the fixture (a dev database gained 115 sessions),
        /// so `docs/product/listing.md` requires capture on a fresh reset DB.
        static func installIfWanted(
            sessions: FileSessionStore,
            scores: FileBoltScoreStore,
            rates: FileRestingRateStore,
            journey: JourneyModel
        ) async -> Bool {
            guard OndApp.wantsDemoPractice else { return false }

            let task = installation
                ?? Task { await write(sessions: sessions, scores: scores, rates: rates) }
            installation = task
            await task.value

            await journey.refresh()
            return true
        }

        /// Replaces whatever this install holds with the fixture. Erases
        /// unconditionally: a simulator used by hand between runs would show
        /// the fixture plus leftovers, and two screenshots a week apart would
        /// not match. The three stores are independent files, so concurrent.
        private static func write(
            sessions: FileSessionStore,
            scores: FileBoltScoreStore,
            rates: FileRestingRateStore
        ) async {
            async let cleared: Void = sessions.erase()
            async let clearedScores: Void = scores.erase()
            async let clearedRates: Void = rates.erase()
            _ = await (cleared, clearedScores, clearedRates)

            // `merge` rather than `record` per session, for the whole array in
            // one write instead of one file rewrite each. Its dedup does nothing
            // here — the erase above leaves it nothing to skip — but the ids it
            // matches on are stable, so a second pass that reached this line
            // would converge rather than double the history.
            _ = await sessions.merge(history())
            for score in pauses() {
                await scores.record(score)
            }
            for rate in restingRates() {
                await rates.record(rate)
            }
        }

        /// SplitMix64 with a fixed seed. Determinism is the requirement — two
        /// runs a week apart must produce the same screenshots — but not
        /// regularity: a fixed daily schedule drew a sawtooth chart no real
        /// month has, and the whole set read as generated.
        private struct Seeded: RandomNumberGenerator {
            private var state: UInt64

            init(seed: UInt64) {
                state = seed
            }

            mutating func next() -> UInt64 {
                state &+= 0x9E37_79B9_7F4A_7C15
                var z = state
                z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
                z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
                return z ^ (z >> 31)
            }
        }

        /// The hours somebody actually sits down. Weighted by repetition —
        /// mornings and evenings carry most of it, with the odd session in the
        /// working day. A day draws from this without replacement, so the
        /// weighting biases the first sitting and every later one lands
        /// somewhere else in the day.
        private static let hours = [7, 8, 8, 8, 9, 12, 13, 17, 21, 21, 22]

        /// A stable id, drawn from the seeded generator — the half of
        /// idempotence `merge` cannot supply. Random ids made every pass new
        /// to the store: nine passes put 495 sessions across 42 days. Raw
        /// bytes, not a formatted string: `UUID(uuidString:) ?? UUID()` has a
        /// fallback that silently makes the ids random again; this cannot fail.
        private static func identifier(using rng: inout Seeded) -> UUID {
            var bytes = (rng.next(), rng.next())
            return withUnsafeBytes(of: &bytes) { UUID(uuid: $0.load(as: uuid_t.self)) }
        }

        /// The sessions, oldest first.
        private static func history() -> [SessionRecord] {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: .now)
            // Any constant does; this one spells "ondbreat".
            var rng = Seeded(seed: 0x6F6E_6462_7265_6174)
            var records: [SessionRecord] = []

            for offset in stride(from: span - 1, through: 0, by: -1) {
                guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else {
                    continue
                }

                // Drawn without replacement, which is the point: two sittings
                // rolled independently can land in the same hour, and the
                // journal then shows a row repeated under one timestamp — the
                // shape a fabricated history has and a real one does not.
                var free = hours
                for _ in 0 ..< sittings(daysAgo: offset, using: &rng) {
                    guard let hour = free.randomElement(using: &rng) else { break }
                    free.removeAll { $0 == hour }
                    records.append(session(on: day, at: hour, using: &rng))
                }
            }

            return records
        }

        /// How many times somebody sat down on one day.
        ///
        /// Most days one, a good few two, the occasional three — and days off
        /// only ever outside the streak window, because a gap inside it would put
        /// a number on Home that the journal directly beneath contradicts.
        private static func sittings(daysAgo offset: Int, using rng: inout Seeded) -> Int {
            let roll = Int.random(in: 0 ..< 100, using: &rng)

            if offset >= streak, roll < 14 {
                return 0
            }

            return switch roll {
            case ..<70: 1
            case ..<94: 2
            default: 3
            }
        }

        /// One session, at an hour somebody might plausibly have practised.
        private static func session(
            on day: Date,
            at hour: Int,
            using rng: inout Seeded
        ) -> SessionRecord {
            let calendar = Calendar.current
            let technique = techniques.randomElement(using: &rng) ?? techniques[0]
            let startedAt = calendar.date(
                bySettingHour: hour,
                minute: Int.random(in: 0 ..< 60, using: &rng),
                second: 0,
                of: day
            ) ?? day
            // Length and cycle count both come off the technique, the only way
            // they can agree. Independently drawn minutes once gave the
            // physiological sigh — a twenty-four-second exercise —
            // twelve-minute sittings.
            let length = technique.plannedDuration
            let cycles = technique.stages.reduce(0) { $0 + $1.cycles }

            // About one in twelve ends early. `completed` is what separates "the
            // timeline ran out" from "the person stopped", and a journal where
            // every row completed would misrepresent a feature the app makes a
            // point of — ending early is recorded, never punished.
            let ended = Int.random(in: 0 ..< 12, using: &rng) == 0

            return SessionRecord(
                id: identifier(using: &rng),
                techniqueSlug: technique.slug,
                startedAt: startedAt,
                duration: ended ? length / 2 : length,
                cyclesCompleted: ended ? cycles / 2 : cycles,
                breathCount: ended ? cycles / 2 : cycles,
                completed: !ended
            )
        }

        /// Controlled pauses, one a week, improving.
        ///
        /// Rising, because a longer comfortable pause is the direction practice
        /// moves this one.
        private static func pauses() -> [BoltScore] {
            weekly().enumerated().map { week, measuredAt in
                BoltScore(seconds: 18 + week * 3, measuredAt: measuredAt)
            }
        }

        /// Resting rates, one a week, improving.
        ///
        /// Falling, and that is not an inconsistency with the pauses above: a
        /// resting breath that has slowed is the improvement here, which is why
        /// `RestingRateRecording.lowest()` is the personal best.
        private static func restingRates() -> [RestingRate] {
            weekly().enumerated().map { week, measuredAt in
                RestingRate(breathsPerMinute: 14 - week, measuredAt: measuredAt)
            }
        }

        /// One moment a week across the span, oldest first.
        private static func weekly() -> [Date] {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: .now)

            return stride(from: span - 1, through: 0, by: -7).compactMap { offset in
                calendar.date(byAdding: .day, value: -offset, to: today)
                    .flatMap { calendar.date(bySettingHour: 7, minute: 30, second: 0, of: $0) }
            }
        }
    }
#endif

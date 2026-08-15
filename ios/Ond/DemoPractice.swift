#if DEBUG
    import Foundation
    import OndKit

    /// A fixed practice history, installed in place of a real one when
    /// `--ui-testing-demo` is passed.
    ///
    /// The App Store screenshots are why this exists. Home, Progress and the
    /// journal are the screens that carry the listing, and they are also the only
    /// ones that read as broken when they are empty — an install with no history
    /// shows a streak of zero and an empty journal, which is an honest picture of
    /// a fresh install and a useless picture of the app. The alternative is
    /// practising on a simulator every day for six weeks, which nobody will do
    /// again the next time a screen moves.
    ///
    /// **Debug and argument-gated, both.** `ios:archive` builds Release, so none
    /// of this compiles into anything a person could install; the argument then
    /// keeps it out of ordinary Debug launches and the other UI tests, which
    /// assert against states this would overwrite.
    ///
    /// Everything below is derived from the current day rather than written as
    /// literal dates: a fixture with dates in it reads as ancient history the
    /// week after it is written, and a screenshot showing last month's streak is
    /// worse than no screenshot.
    ///
    /// `@MainActor` for [`installation`]: the one-shot guard is mutable static
    /// state, which Swift 6 requires be isolated, and the launch task that calls
    /// this is already on the main actor.
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

        /// The techniques practised, drawn from the bundled catalogue.
        ///
        /// Read from the catalogue's own vocabulary rather than listed here: a
        /// slug with no technique behind it renders as a blank journal row, and
        /// a literal list is exactly how that happens — rename one in
        /// `crates/migrate`'s seed, regenerate `catalogue.json`, and the copy
        /// keeps the dead slug into an App Store screenshot with nothing
        /// failing. `OndKit` ships the export precisely so this resolves with no
        /// server running.
        private static let techniques = CatalogueExport.bundled.techniques

        /// The one installation this process will do, joined by every later
        /// caller rather than repeated.
        ///
        /// The task that calls this runs per appearance of the root view, not
        /// once per launch, and SwiftUI reappears it whenever the scene rebuilds
        /// — seven times in a measured run. Deterministic ids mean those seven
        /// would converge on the same file anyway, so this is not what keeps the
        /// history honest; it is what stops six redundant erase-and-rewrite
        /// passes during a launch that is already seeding six weeks of history.
        ///
        /// Assigned *before* the first await, which is what makes the later
        /// callers wait for the first rather than start their own.
        private static var installation: Task<Void, Never>?

        /// Installs the fixture if this launch asked for one, and reports
        /// whether it did — so the caller can skip the sync it replaces.
        ///
        /// Replacing rather than preceding the sync is deliberate — six weeks of
        /// invented practice is the last thing any environment should be told
        /// about, and `journey.sync()` is what would tell it. The refresh then
        /// reads back what was just written, which is what the screens render.
        ///
        /// **It is not sufficient, and the capture procedure assumes as much.**
        /// Skipping the launch sync does not make the fixture local: something
        /// else drains it — a dev database accumulated 115 sessions across two
        /// capture runs — and they come back down on the next launch that
        /// reaches a server. Closing that properly means finding the other
        /// drain; until then `docs/product/listing.md` requires the capture run
        /// against a database `dev:db:reset` has just rebuilt, which contains
        /// the mess rather than preventing it.
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

        /// Replaces whatever this install holds with the fixture.
        ///
        /// Erases first, and erases unconditionally: a simulator used by hand
        /// between runs would otherwise show the fixture plus whatever was
        /// already there, and two screenshots taken a week apart would not
        /// match. The three stores are independent files, so they clear and
        /// fill concurrently.
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

        /// A generator with a fixed seed.
        ///
        /// Determinism is the requirement — two runs a week apart must produce
        /// the same screenshots — but determinism is not regularity, and the
        /// first version of this confused the two. A session every day at 08:15,
        /// a second every third day, a rest every ninth: the practice chart drew
        /// a sawtooth no real month has, and the whole set read as generated.
        /// SplitMix64 is four lines and buys spacing that reads as a person.
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

        /// A stable id for a fixture record.
        ///
        /// Drawn from the seeded generator rather than made fresh, so every
        /// install produces the same ids — which is the half of idempotence
        /// that `merge` cannot supply on its own. Random ids made every pass a
        /// set of sessions the store had never seen, and merge dutifully kept
        /// them all: nine passes put 495 sessions across 42 days on Home, up to
        /// twenty in a day, which is what the practice chart drew.
        ///
        /// Built from the raw bytes and not from a formatted string, because
        /// there must be no way for this to fail: the string form ended
        /// `UUID(uuidString:) ?? UUID()`, and that fallback is indistinguishable
        /// from working right up until it silently makes the ids random again.
        /// This has no failure branch to take.
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
            // Length and cycle count both come off the technique, which is the
            // only way they can agree with each other. A pool of plausible
            // minutes drawn independently gave the physiological sigh — a
            // twenty-four-second exercise — twelve-minute sittings, and a
            // journal row saying so is the kind of detail that reads as
            // invented precisely because nobody can say why.
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

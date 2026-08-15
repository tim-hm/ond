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

        /// The slugs practised, cycled in order.
        ///
        /// Read from the bundled catalogue's own vocabulary rather than invented:
        /// a slug with no technique behind it renders as a blank row, and
        /// `OndKit` ships `catalogue.json` precisely so this resolves with no
        /// server running.
        private static let techniques = [
            "box-breathing",
            "coherent-breathing",
            "four-seven-eight",
            "extended-exhale",
            "physiological-sigh",
            "cyclic-sighing",
        ]

        /// Session lengths in minutes, cycled alongside the techniques so the
        /// journal shows a mix rather than a column of identical rows.
        private static let minutes = [4, 6, 5, 10, 3, 8]

        /// Replaces whatever this install holds with the fixture.
        ///
        /// Erases first, and erases unconditionally: a simulator that has been
        /// used by hand between runs would otherwise show the fixture plus
        /// whatever was already there, and two screenshots taken a week apart
        /// would not match.
        static func install(
            sessions: FileSessionStore,
            scores: FileBoltScoreStore,
            rates: FileRestingRateStore
        ) async {
            await sessions.erase()
            await scores.erase()
            await rates.erase()

            for record in history() {
                await sessions.record(record)
            }
            for score in pauses() {
                await scores.record(score)
            }
            for rate in restingRates() {
                await rates.record(rate)
            }
        }

        /// The sessions, oldest first.
        private static func history() -> [SessionRecord] {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: .now)
            var records: [SessionRecord] = []

            for offset in stride(from: span - 1, through: 0, by: -1) {
                guard !isGap(offset) else { continue }
                guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else {
                    continue
                }

                records.append(session(on: day, offset: offset, evening: false))

                // A second sitting every third day. Practice that is one
                // identical session per day for six weeks looks generated,
                // which is the one thing a screenshot must not look.
                if offset % 3 == 1 {
                    records.append(session(on: day, offset: offset, evening: true))
                }
            }

            return records
        }

        /// One session, placed at a plausible hour.
        private static func session(on day: Date, offset: Int, evening: Bool) -> SessionRecord {
            let calendar = Calendar.current
            let index = (offset + (evening ? 3 : 0)) % techniques.count
            let length = minutes[index]
            let startedAt = calendar.date(
                bySettingHour: evening ? 21 : 8,
                minute: evening ? 40 : 15,
                second: 0,
                of: day
            ) ?? day
            // One cycle every sixteen seconds is the shape of box breathing at
            // the catalogue's default pace. It is an approximation for the other
            // five, and the journal shows duration rather than cycle count, so
            // the cost of that is a number nothing displays being slightly wrong.
            let cycles = max(1, (length * 60) / 16)

            // Two sessions in the whole history end early. `completed` is what
            // separates "the timeline ran out" from "the person stopped", and a
            // journal where every row completed would misrepresent a feature the
            // app makes a point of — ending early is recorded, never punished.
            let ended = offset == 17 || offset == 29

            return SessionRecord(
                techniqueSlug: techniques[index],
                startedAt: startedAt,
                duration: .seconds(ended ? (length * 60) / 2 : length * 60),
                cyclesCompleted: ended ? cycles / 2 : cycles,
                breathCount: ended ? cycles / 2 : cycles,
                completed: !ended
            )
        }

        /// Whether nothing was practised this many days ago.
        ///
        /// Deliberately outside the streak window — see [`streak`].
        private static func isGap(_ offset: Int) -> Bool {
            offset >= streak && offset % 9 == 4
        }

        /// Controlled pauses, one a week, improving.
        ///
        /// Rising, because a longer comfortable pause is the direction practice
        /// moves this one.
        private static func pauses() -> [BoltScore] {
            weekly(span: span).enumerated().map { week, measuredAt in
                BoltScore(seconds: 18 + week * 3, measuredAt: measuredAt)
            }
        }

        /// Resting rates, one a week, improving.
        ///
        /// Falling, and that is not an inconsistency with the pauses above: a
        /// resting breath that has slowed is the improvement here, which is why
        /// `RestingRateRecording.lowest()` is the personal best.
        private static func restingRates() -> [RestingRate] {
            weekly(span: span).enumerated().map { week, measuredAt in
                RestingRate(breathsPerMinute: 14 - week, measuredAt: measuredAt)
            }
        }

        /// One moment a week across the span, oldest first.
        private static func weekly(span: Int) -> [Date] {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: .now)

            return stride(from: span - 1, through: 0, by: -7).compactMap { offset in
                calendar.date(byAdding: .day, value: -offset, to: today)
                    .flatMap { calendar.date(bySettingHour: 7, minute: 30, second: 0, of: $0) }
            }
        }
    }
#endif

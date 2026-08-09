import Foundation
import Observation
import os

/// What the journey tab shows, and where it comes from.
///
/// Two sources with different rules, and the split is the whole design. The
/// person's own numbers — totals, streaks, history, best pause — are folded from
/// the local stores and are therefore always there, immediately, offline. The
/// leaderboards are other people, so they need a connection and say so quietly
/// when there isn't one. Nothing on this screen ever waits on the network.
@MainActor
@Observable
public final class JourneyModel {
    /// A board is either not asked for yet, on its way, here, out of reach, or
    /// waiting on an answer only this person can give.
    ///
    /// `unreachable` rather than an error case: being offline is a normal state
    /// for a phone, not a fault to report.
    public enum LeaderboardState: Sendable, Equatable {
        case idle
        case loading
        case loaded(Leaderboard)
        case unreachable
        /// The decade board, asked for by somebody who has not said which
        /// decade. Its own case because it is the one leaderboard failure with
        /// an action attached, and the scope picker can offer it before the
        /// server has the band: `LeaderboardView` guards on the *local* profile
        /// value, which is set the moment it is picked and outruns the sync.
        case needsBirthYearBand
    }

    public private(set) var stats: JourneyStats = .none
    /// Every session, newest first. The numbers above the strip are folded from
    /// all of it; `visibleHistory` is the part a screen draws.
    public private(set) var history: [SessionRecord] = []
    /// The best controlled pause on this device, `nil` before the first test.
    public private(set) var personalBest: Int?
    /// The slowest resting rate on this device, `nil` before the first count.
    /// Lowest is the good end — see `RestingRateRecording.lowest()`.
    public private(set) var lowestRestingRate: Int?

    public private(set) var leaderboard: LeaderboardState = .idle
    public var board: LeaderboardBoard = .streak
    public var scope: LeaderboardScope = .global

    /// How many rows the strip shows before it is asked for more — the server's
    /// own page size, so one reveal is one page of history either way.
    private static let page = 50

    /// How much of `history` the strip is showing, in rows.
    ///
    /// It only ever grows, so a delete or a sync that refolds everything does
    /// not roll the strip back up under somebody who had opened it.
    private var shown = JourneyModel.page

    private static let logger = Logger(category: "leaderboard")

    private let sessions: any SessionRecording
    private let scores: any BoltScoreRecording
    private let rates: any RestingRateRecording
    private let journeys: any JourneySyncing
    private let queue: SessionSyncQueue

    public init(
        sessions: any SessionRecording,
        scores: any BoltScoreRecording,
        rates: any RestingRateRecording,
        journeys: any JourneySyncing,
        queue: SessionSyncQueue
    ) {
        self.sessions = sessions
        self.scores = scores
        self.rates = rates
        self.journeys = journeys
        self.queue = queue
    }

    /// The rows the phone's strip draws: the most recent page, newest first.
    ///
    /// Bounded because the full list grows for the life of the install and the
    /// strip is not a document — somebody three years in has a thousand rows
    /// and reads the last few. The wrist takes its own five off `history`
    /// instead: that is a layout, not a page, and it never grows.
    public var visibleHistory: ArraySlice<SessionRecord> {
        history.prefix(shown)
    }

    public var hasEarlierSessions: Bool {
        history.count > shown
    }

    /// Widens the strip by another page, over the history already in hand —
    /// which is why revealing more of it touches neither disk nor network.
    public func revealEarlierSessions() {
        shown += Self.page
    }

    /// Reads the local stores and fills the screen.
    ///
    /// Called on every appearance. It touches no network, so it is as fast in
    /// airplane mode as anywhere else — which is exactly why the tab does not
    /// have a loading state for its own numbers.
    public func refresh() async {
        refreshGeneration += 1
        let generation = refreshGeneration

        let recorded = await sessions.recordedSessions()
        let best = await scores.personalBest()
        let slowest = await rates.lowest()
        let (folded, newestFirst) = await Self.fold(recorded)

        // Newest wins. The fold now suspends, so a refresh that read the
        // stores before a delete could assign after it — putting the deleted
        // row back on screen with its numbers. The sync queue's identity
        // epoch, one layer up.
        guard generation == refreshGeneration else { return }
        stats = folded
        history = newestFirst
        personalBest = best
        lowestRestingRate = slowest
    }

    /// Bumped at the top of every [`refresh()`](JourneyModel.refresh), so an
    /// older refresh resumed past a newer one discards itself.
    private var refreshGeneration = 0

    /// The whole fold, off the main actor.
    ///
    /// Two reduces, a day set, a `dateComponents` per unique day and a full
    /// sort all grow with the history, so a thousand-session install was
    /// paying a few milliseconds of main-thread time on every appearance of
    /// the tab and after every delete. The fold is pure and `SessionRecord`
    /// is `Sendable`; `nonisolated` is what hops it onto the concurrent
    /// executor, and only the results come back to the actor.
    private nonisolated static func fold(
        _ recorded: [SessionRecord]
    ) async -> (JourneyStats, [SessionRecord]) {
        (
            JourneyStats(sessions: recorded),
            recorded.sorted { $0.startedAt > $1.startedAt }
        )
    }

    /// Pushes anything outstanding, then re-reads — a restore may have brought
    /// history back that this device had lost.
    ///
    /// Deliberately separate from `refresh()` so the screen is drawn before this
    /// is even started.
    public func sync() async {
        // Only a restore changes what is on this device, and it happens once
        // after a reinstall — re-reading both files on every sync would be work
        // for nothing on every run after it.
        if await queue.sync() {
            await refresh()
        }
    }

    /// The same sync, for the launch where the identity changed under it.
    ///
    /// Signing in can hand this device an older identity than the one it
    /// arrived with, and the history behind that id is exactly what the person
    /// signed in to get back. `sync()` would not go looking: its restore runs
    /// once per queue, because only a reinstall used to change the answer.
    public func syncAdoptedIdentity() async {
        await queue.syncAdoptedIdentity()
        // Unconditionally, unlike `sync()`: the paths that land here — signing
        // in, signing out, deleting — may have emptied or swapped the stores
        // whether or not the restore brought anything back. Here rather than
        // at the caller, so the fold runs exactly once instead of once for
        // the restore and again for the caller's certainty.
        await refresh()
    }

    /// Stores a controlled-pause measurement and answers whether it is a new
    /// best.
    ///
    /// The verdict is local, because the number a person is looking at has to be
    /// right with no signal. The server holds the same history and reaches the
    /// same answer for the leaderboard.
    @discardableResult
    public func record(boltSeconds seconds: Int) async -> Bool {
        let previous = personalBest
        await scores.record(BoltScore(seconds: seconds))
        // Derived from what is already in hand rather than re-read: the file was
        // just written, and the new best can only be one of these two.
        personalBest = max(previous ?? 0, seconds)

        // Not awaited: the result screen is already on its way, and the upload
        // has the rest of the app's lifetime to succeed in.
        Task { await queue.sync() }

        return previous.map { seconds > $0 } ?? true
    }

    /// Stores a resting-rate measurement and answers whether it is a new lowest.
    ///
    /// Lowest, not highest — this is the one measurement in the app that reads
    /// backwards, and everything else about the shape matches the pause above:
    /// the verdict is local so the number is right with no signal, and the
    /// upload happens behind the result screen.
    @discardableResult
    public func record(restingBreaths breaths: Int) async -> Bool {
        let previous = lowestRestingRate
        await rates.record(RestingRate(breathsPerMinute: breaths))
        lowestRestingRate = min(previous ?? breaths, breaths)

        Task { await queue.sync() }

        return previous.map { breaths < $0 } ?? true
    }

    /// Deletes one session from the journal and refolds everything derived
    /// from it — totals, streaks, the history strip — in the same breath, so
    /// the screen never shows numbers that still count a row it no longer has.
    public func delete(_ record: SessionRecord) async {
        await sessions.remove(record.id)
        await refresh()
    }

    /// Fetches the current board, if the network allows.
    ///
    /// The one failure that is separated out is the one somebody can do
    /// something about. Everything else — no signal, a server that is down, a
    /// board this build cannot read — is the same quiet notice, because there is
    /// no action behind any of them.
    public func loadLeaderboard() async {
        leaderboard = .loading

        do {
            leaderboard = try await .loaded(journeys.leaderboard(board, scope: scope))
        } catch JourneyRepositoryError.failedPrecondition {
            leaderboard = .needsBirthYearBand
        } catch {
            // "Unreachable" is all the screen says and all it should say. The
            // cause still belongs somewhere, or a board that is down for one
            // build and one build only is indistinguishable from a train
            // tunnel. Read out first because the message is an autoclosure,
            // where a property read needs a `self.` SwiftFormat then deletes.
            let requested = board
            Self.logger
                .notice(
                    "the \(requested.rawValue, privacy: .public) leaderboard is unreachable: \(error.localizedDescription, privacy: .public)"
                )
            leaderboard = .unreachable
        }
    }
}

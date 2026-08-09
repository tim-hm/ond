import Foundation
import os

/// Drains the local stores into the server, and never the other way round for
/// anything the screen needs.
///
/// The app is offline-first: the file on this device is the source of truth, and
/// this queue is how the server finds out about it. Nothing here blocks a view,
/// nothing here throws at a caller, and a failed run leaves the ledger untouched
/// so the next one picks up exactly what was missed.
///
/// The ledger is a set of acknowledged ids rather than a high-water timestamp.
/// A timestamp assumes sessions arrive in order, which they do not — a watch
/// session recorded on Tuesday can reach the file after Wednesday's — and would
/// silently skip anything that landed behind the mark.
public actor SessionSyncQueue: PersonalStore {
    private static let logger = Logger(category: "journey-sync")

    private static let acknowledgedSessionsKey = "journey.acknowledgedSessions"
    private static let acknowledgedScoresKey = "journey.acknowledgedBoltScores"
    private static let acknowledgedRatesKey = "journey.acknowledgedRestingRates"

    /// Matches the server's own cap on one `RecordSessions` call. A backlog
    /// larger than this drains over several runs rather than being refused.
    private static let maxBatch = 200

    /// How many restore pages one run will walk before giving up.
    ///
    /// At the page size the repository asks for this is more history than a
    /// lifetime of daily practice, so reaching it means the server is handing
    /// back a token it should not — and a loop that trusted the token alone
    /// would run forever on a foreground. Logged at `error` because it can only
    /// be a bug on one side or the other.
    private static let maxRestorePages = 40

    private let sessions: any SessionRecording
    private let scores: any BoltScoreRecording
    private let rates: any RestingRateRecording
    private let journeys: any JourneySyncing
    private let tombstones: (any TombstoneStoring)?
    private let ledger: SyncLedger

    /// Whether a restore has walked the server's history to the end since this
    /// queue was built.
    ///
    /// Restore is the one step here that reaches the server whether or not
    /// anything is outstanding: it asks for history this device may have lost,
    /// and nothing local can predict the answer. That question is worth asking
    /// once a run — only a reinstall makes it return anything — and `sync()` is
    /// called on every visit to the journey, which under a tab bar is as often
    /// as somebody taps it.
    ///
    /// Set only where the walk finished. A run that threw leaves this false, so
    /// a device that launched with no signal still restores on a later one.
    private var hasRestored = false

    /// Which identity's world this queue is syncing, bumped first thing by the
    /// two transitions that change the answer — an erasure and an adoption —
    /// and captured at the start of every sync step. Actor reentrancy lets
    /// either transition run while a step is suspended at an await, and a step
    /// that resumed into a different epoch is holding the *old* identity's
    /// world: merging it would resurrect what an erasure just deleted, sending
    /// it would stamp the old person's data with the new person's id, and its
    /// `hasRestored = true` would cancel the restore the transition reopened.
    private var identityEpoch = 0

    /// - Parameter tombstones: where deletions wait for the server. Optional
    ///   because `SessionRecording` cannot express it — a caller that has only
    ///   the recording seam still syncs, it just never drains deletions, which
    ///   is the behaviour that existed before `DeleteSessions` did.
    public init(
        sessions: any SessionRecording,
        scores: any BoltScoreRecording,
        rates: any RestingRateRecording,
        journeys: any JourneySyncing,
        tombstones: (any TombstoneStoring)? = nil,
        ledger: SyncLedger = SyncLedger()
    ) {
        self.sessions = sessions
        self.scores = scores
        self.rates = rates
        self.journeys = journeys
        self.tombstones = tombstones
        self.ledger = ledger
    }

    /// Sends whatever the server has not acknowledged, then takes back anything
    /// it holds that this device has lost.
    ///
    /// Safe to call on every foreground, after every session, and on every
    /// appearance of the journey: with nothing outstanding it touches the
    /// network not at all once the restore below has run, and being an actor is
    /// what stops two of those overlapping into a double send.
    ///
    /// - Returns: whether the local stores changed, which only a restore can do.
    ///   Sending changes nothing on this device, so a caller that re-reads on
    ///   every sync would re-read for nothing on all but the first run after a
    ///   reinstall.
    @discardableResult
    public func sync() async -> Bool {
        // Deletions go first so the restore at the end reads a server that has
        // already forgotten them. Any other order would have the same run pull
        // back sessions this one was about to delete, and leave the tombstones
        // doing the filtering for another cycle.
        await sendDeletions()
        await sendSessions()
        await sendScores()
        await sendRates()

        guard !hasRestored else { return false }
        return await restore()
    }

    /// Syncs, and walks the server's history again whatever this queue has
    /// already restored.
    ///
    /// For the one event that makes an answered restore stale: adopting a
    /// different identity. Signing in on a second device hands this install the
    /// id whose history it came for, and the queue is built once at launch — so
    /// without this the journey shows nothing until the app is next relaunched,
    /// which is not a person restoring their practice.
    ///
    /// - Returns: whatever `sync()` returns — whether the local stores changed.
    @discardableResult
    public func syncAdoptedIdentity() async -> Bool {
        // Bumped so a walk still in flight for the old identity abandons at
        // its next guard. Left to resume, it could set `hasRestored = true`
        // after this reset and skip the very restore signing in is for.
        identityEpoch += 1
        hasRestored = false
        return await sync()
    }

    /// Forgets what the server acknowledged, because there is no longer a server
    /// row that acknowledged it.
    ///
    /// The ledger is ids and nothing else, but it is ids of this person's
    /// sessions and it decides what gets sent. Left behind, it would answer for
    /// an identity that no longer exists: the stores it prunes against are being
    /// emptied in the same breath, so every entry in it is about practice that
    /// has just been erased.
    ///
    /// The restore is reopened for the same reason it is after a sign-in — the
    /// question "what does the server hold for me" has a new answer, and this
    /// queue had already stopped asking.
    public func erase() async {
        identityEpoch += 1
        ledger.forget(Self.acknowledgedSessionsKey)
        ledger.forget(Self.acknowledgedScoresKey)
        ledger.forget(Self.acknowledgedRatesKey)
        hasRestored = false
    }

    /// Tells the server about sessions deleted here, and forgets the tombstone
    /// only once it has said so.
    ///
    /// The order is the whole point: a tombstone dropped before the server
    /// confirmed would let the next restore hand the session back, which is the
    /// resurrection this exists to prevent. A failed call leaves the file
    /// untouched and the next run tries again.
    private func sendDeletions() async {
        guard let tombstones else { return }

        let epoch = identityEpoch
        let pending = await tombstones.tombstonedSessions()
        guard !pending.isEmpty, identityEpoch == epoch else { return }

        let batch = Array(pending.prefix(Self.maxBatch))
        do {
            try await journeys.delete(batch)
            await tombstones.forgetTombstones(batch)
        } catch {
            Self.logger
                .notice(
                    "session deletion deferred: \(error.localizedDescription, privacy: .public)"
                )
        }
    }

    private func sendSessions() async {
        let epoch = identityEpoch
        let recorded = await sessions.recordedSessions()
        guard identityEpoch == epoch else { return }
        var acknowledged = ledger.acknowledged(
            Self.acknowledgedSessionsKey,
            keeping: recorded.map(\.id)
        )
        // Written on every run, not only a successful send: the read above has
        // already dropped ids whose sessions are gone, and that pruning is what
        // stops the ledger growing for the life of the install. `store` itself
        // skips the write when nothing moved. Skipped across an epoch — the
        // ids in hand are the old identity's.
        defer {
            if identityEpoch == epoch {
                ledger.store(acknowledged, at: Self.acknowledgedSessionsKey)
            }
        }

        let pending = recorded.filter { !acknowledged.contains($0.id) }
        guard !pending.isEmpty else { return }

        let batch = Array(pending.prefix(Self.maxBatch))
        do {
            try await journeys.record(batch)
            acknowledged.formUnion(batch.map(\.id))
        } catch {
            // Not surfaced: a session that syncs a day late costs the person
            // nothing, and there is no action they could take from a view.
            Self.logger
                .notice("session sync deferred: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func sendScores() async {
        let epoch = identityEpoch
        let recorded = await scores.recordedScores()
        await sendMeasurements(
            recorded,
            begun: epoch,
            at: Self.acknowledgedScoresKey,
            named: "bolt"
        ) {
            try await journeys.record($0)
        }
    }

    private func sendRates() async {
        let epoch = identityEpoch
        let recorded = await rates.recordedRates()
        await sendMeasurements(
            recorded,
            begun: epoch,
            at: Self.acknowledgedRatesKey,
            named: "resting rate"
        ) {
            try await journeys.record($0)
        }
    }

    /// Sends whichever measurements the server has not acknowledged, one call
    /// each rather than a batch: the RPC behind each takes a single reading, and
    /// somebody accumulates these one deliberate test at a time.
    ///
    /// Generic over the measurement rather than written once per store. What is
    /// shared is not the three lines of loop but the epoch and ledger discipline
    /// around them — prune on every run, write only on a change, abandon the
    /// moment the identity changes under a suspended send — and that is the part
    /// worth having exactly one copy of.
    ///
    /// - Parameters:
    ///   - recorded: everything this device holds, already read from its store.
    ///   - epoch: the identity epoch the read happened under. Anything that
    ///     resumes into a different one is holding the old identity's history.
    ///   - key: where the acknowledged ids live in the ledger.
    ///   - name: what these are called in the log a deferred send leaves behind.
    ///   - send: hands one measurement to the server.
    private func sendMeasurements<Measurement: Identifiable & Sendable>(
        _ recorded: [Measurement],
        begun epoch: Int,
        at key: String,
        named name: String,
        with send: (Measurement) async throws -> Void
    ) async where Measurement.ID == UUID {
        guard identityEpoch == epoch else { return }
        var acknowledged = ledger.acknowledged(key, keeping: recorded.map(\.id))
        defer {
            if identityEpoch == epoch {
                ledger.store(acknowledged, at: key)
            }
        }

        let pending = recorded.filter { !acknowledged.contains($0.id) }
        guard !pending.isEmpty else { return }

        for measurement in pending.prefix(Self.maxBatch) {
            do {
                try await send(measurement)
                // Re-checked per send, not only at the ledger: the identity is
                // read per request, so a loop resumed across an epoch would
                // stamp the old person's remaining readings with the new id.
                guard identityEpoch == epoch else { return }
                acknowledged.insert(measurement.id)
            } catch {
                Self.logger
                    .notice(
                        "\(name, privacy: .public) sync deferred: \(error.localizedDescription, privacy: .public)"
                    )
                break
            }
        }
    }

    /// Pulls back every session the server holds and this device does not.
    ///
    /// The Keychain identity survives a reinstall while the sessions file does
    /// not, so this is what stops somebody's streak vanishing because they
    /// changed phones. Anything restored is acknowledged on arrival — it came
    /// from the server, so sending it back would be pure noise.
    ///
    /// Pages until the server stops offering a token. A single call would return
    /// only the newest page, and the totals and streaks that come back alongside
    /// it would be right — which is what makes a truncated restore so hard to
    /// notice, and why this loop stops only on an exhausted history or a failed
    /// request.
    ///
    /// A failed page keeps whatever earlier ones brought back rather than
    /// discarding it: the merge is idempotent on session id and the next run
    /// starts again from the newest page, so a partial restore costs a repeat
    /// rather than a gap.
    ///
    /// Pages are gathered and landed once, whatever ended the walk: one file
    /// rewrite per run rather than one per each of up to 40 pages of 500.
    private func restore() async -> Bool {
        let epoch = identityEpoch
        var fetched: [SessionRecord] = []
        var pageToken: String?

        for _ in 0 ..< Self.maxRestorePages {
            do {
                let page = try await journeys.storedSessions(after: pageToken)
                // Resumed across an epoch: what was fetched is the old
                // identity's history, and `hasRestored` must keep the false
                // the transition gave it.
                guard identityEpoch == epoch else { return false }
                fetched.append(contentsOf: page.sessions)

                guard let next = page.nextPageToken else {
                    hasRestored = true
                    return await land(fetched, begun: epoch)
                }
                pageToken = next
            } catch {
                Self.logger
                    .notice(
                        "journey restore deferred: \(error.localizedDescription, privacy: .public)"
                    )
                return await land(fetched, begun: epoch)
            }
        }

        // Counted as restored even though the history was not exhausted. The
        // ceiling can only mean the server is handing back a token it should
        // not, and retrying on every appearance would multiply that bug by
        // every tap on the tab rather than by every launch.
        hasRestored = true
        Self.logger.error("journey restore stopped at the page ceiling")
        return await land(fetched, begun: epoch)
    }

    /// Lands what a restore walk brought back: one merge, one acknowledgement.
    ///
    /// `begun` is the walk's epoch. A walk that outlived an erasure lands
    /// nothing; one the erasure interleaves *during* the merge still ends
    /// erased, because the composition root erases the queue before the store —
    /// so the store runs this merge first and the erasure after it — and the
    /// acknowledgement is skipped here.
    ///
    /// - Returns: whether the local stores changed.
    private func land(_ fetched: [SessionRecord], begun epoch: Int) async -> Bool {
        guard !fetched.isEmpty, identityEpoch == epoch else { return false }

        let changed = await sessions.merge(fetched)
        guard identityEpoch == epoch else { return changed }
        // Union rather than a fresh prune: `sendSessions` has already pruned
        // this key on the way past, and re-deriving the present ids would mean
        // reading the whole session file again to learn what was just written
        // to it.
        ledger.acknowledge(fetched.map(\.id), at: Self.acknowledgedSessionsKey)
        return changed
    }
}

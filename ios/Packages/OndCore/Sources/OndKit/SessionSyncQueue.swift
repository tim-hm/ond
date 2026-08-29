import Foundation
import os

/// Drains the local stores into the server; the device's file stays the source
/// of truth. Nothing here blocks a view or throws at a caller, and a failed
/// run leaves the ledger untouched for the next one. The ledger is a set of
/// acknowledged ids, not a high-water timestamp: sessions arrive out of order,
/// and a timestamp would silently skip anything landing behind the mark.
public actor SessionSyncQueue: PersonalStore {
    static let logger = Logger(category: "journey-sync")

    static let acknowledgedSessionsKey = "journey.acknowledgedSessions"
    private static let acknowledgedScoresKey = "journey.acknowledgedBoltScores"
    private static let acknowledgedRatesKey = "journey.acknowledgedRestingRates"

    /// Matches the server's own cap on one `RecordSessions` call. A backlog
    /// larger than this drains over several runs rather than being refused.
    private static let maxBatch = 200

    /// How many restore pages one run will walk before giving up. At the page
    /// size the repository asks for this is more than a lifetime of daily
    /// practice, so reaching it means the server hands back a token it should
    /// not — and a loop that trusted the token alone would run forever.
    static let maxRestorePages = 40

    let sessions: any SessionRecording
    private let scores: any BoltScoreRecording
    private let rates: any RestingRateRecording
    let journeys: any JourneySyncing
    private let tombstones: (any TombstoneStoring)?
    let ledger: SyncLedger

    /// Whether a restore has walked the server's history to the end since this
    /// queue was built. Restore reaches the server even with nothing
    /// outstanding, and `sync()` runs on every visit to the journey — so the
    /// question is asked once per launch. Set only where the walk finished: a
    /// run that threw leaves this false, so a later sync still restores.
    var hasRestored = false

    /// Which identity's world this queue syncs — bumped first thing by an
    /// erasure or an adoption, captured at the start of every sync step. Actor
    /// reentrancy lets either run while a step is suspended; a step resumed
    /// into a new epoch holds the old identity's world: merging it resurrects
    /// erased data, sending misattributes it, `hasRestored` cancels the restore.
    var identityEpoch = 0

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
    /// it holds that this device has lost. Safe to call on every foreground and
    /// appearance: with nothing outstanding it touches the network not at all
    /// once restore has run, and the actor stops two calls overlapping into a
    /// double send. Returns whether local stores changed; only a restore can.
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
    /// already restored. For the one event that makes an answered restore
    /// stale: adopting a different identity. The queue is built once at
    /// launch, so without this the journey shows nothing until the next
    /// relaunch. Returns whatever `sync()` returns.
    @discardableResult
    public func syncAdoptedIdentity() async -> Bool {
        // Bumped so a walk still in flight for the old identity abandons at
        // its next guard. Left to resume, it could set `hasRestored = true`
        // after this reset and skip the very restore signing in is for.
        identityEpoch += 1
        hasRestored = false
        return await sync()
    }

    /// Forgets what the server acknowledged: there is no longer a server row
    /// that acknowledged it. Left behind, the ledger would answer for an
    /// identity that no longer exists — the stores it prunes against are being
    /// emptied in the same breath. The restore reopens because "what does the
    /// server hold for me" has a new answer.
    public func erase() async {
        identityEpoch += 1
        ledger.forget(Self.acknowledgedSessionsKey)
        ledger.forget(Self.acknowledgedScoresKey)
        ledger.forget(Self.acknowledgedRatesKey)
        hasRestored = false
    }

    /// Tells the server about sessions deleted here, and forgets the tombstone
    /// only once it has said so. A tombstone dropped before the server
    /// confirmed would let the next restore hand the session back. A failed
    /// call leaves the file untouched and the next run tries again.
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
                    "session deletion deferred: \(error.diagnostic, privacy: .public)"
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
                .notice("session sync deferred: \(error.diagnostic, privacy: .public)")
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
    /// each rather than a batch: the RPC behind each takes a single reading.
    /// Generic because the shared part is the epoch and ledger discipline —
    /// prune on every run, write only on a change, abandon when the identity
    /// changes under a suspended send. `epoch` is when `recorded` was read.
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
                        "\(name, privacy: .public) sync deferred: \(error.diagnostic, privacy: .public)"
                    )
                break
            }
        }
    }
}

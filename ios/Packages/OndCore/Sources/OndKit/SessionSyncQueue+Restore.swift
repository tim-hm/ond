import Foundation

/// The half of the sync that pulls history down: the walk a reinstall needs, the
/// single page a wrist's notice needs, and the one merge both land through.
///
/// Split from `SessionSyncQueue.swift` for file length, along the seam the two
/// halves already had — everything there pushes up, everything here pulls down,
/// and they meet only at the ledger and the identity epoch. Those members lose
/// their `private` to make the split possible; they stay actor-isolated, so what
/// it costs is a name visible inside the module rather than any of the isolation
/// that makes this safe.
extension SessionSyncQueue {
    /// Fetches the newest page of the server's history, for the notice that
    /// another device has just added to it.
    ///
    /// One page rather than the walk `sync()` does, because the question is
    /// smaller: the wrist has finished one session, and a session recorded a
    /// moment ago is on the newest page by construction. The walk exists for a
    /// reinstall, where the question is "everything I have lost", and running it
    /// per notice would page a lifetime of practice to collect one half-hour.
    ///
    /// Deliberately not `sync()`, so `hasRestored` is neither read nor written. A
    /// notice is not evidence about the walk: the wrist sends one the moment a
    /// session ends, which can be before its own upload has landed, and a
    /// reopened walk that then found nothing would mark the launch's restore
    /// answered and hide the very session it came for. It sends nothing either —
    /// a notice says the server has something, not that this device does.
    ///
    /// - Returns: whether the local stores changed.
    @discardableResult
    public func restoreNewestSessions() async -> Bool {
        let epoch = identityEpoch
        do {
            let page = try await journeys.storedSessions(after: nil)
            // Resumed across an epoch: the page belongs to whoever this device
            // used to be, and `land` would merge an erased person's practice back
            // into files an erasure has just emptied.
            guard identityEpoch == epoch else { return false }
            return await land(page.sessions, begun: epoch)
        } catch {
            Self.logger
                .notice(
                    "the wrist's session could not be fetched: \(error.localizedDescription, privacy: .public)"
                )
            return false
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
    func restore() async -> Bool {
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
    func land(_ fetched: [SessionRecord], begun epoch: Int) async -> Bool {
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

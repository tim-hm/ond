import Foundation

/// The half of the sync that pulls history down: the reinstall walk, the
/// wrist notice's single page, and the one merge both land through. Split from
/// `SessionSyncQueue.swift` for file length; the members both halves touch
/// lose `private` but stay actor-isolated, so the split costs a module-visible
/// name and none of the isolation.
extension SessionSyncQueue {
    /// Fetches the newest page of the server's history, for the notice that
    /// another device has just added to it. One page, not `sync()`'s walk: a
    /// session recorded moments ago is on the newest page. `hasRestored` is
    /// neither read nor written — the notice can precede the wrist's own
    /// upload, and a walk finding nothing would hide the session it came for.
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
                    "the wrist's session could not be fetched: \(error.diagnostic, privacy: .public)"
                )
            return false
        }
    }

    /// Pulls back every session the server holds and this device does not —
    /// the Keychain identity survives a reinstall, the sessions file does not.
    /// Pages until the server stops offering a token; a failed page keeps what
    /// earlier ones brought, since the merge is idempotent on id and the next
    /// run starts over. Pages land once: one file rewrite per run, not per page.
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
                        "journey restore deferred: \(error.diagnostic, privacy: .public)"
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
    /// `begun` is the walk's epoch; a walk that outlived an erasure lands
    /// nothing. An erasure interleaved mid-merge still ends erased — the
    /// composition root erases the queue before the store — and the
    /// acknowledgement is skipped. Returns whether the local stores changed.
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

import Foundation

/// The ids of sessions this device deleted and the server may still hold.
/// Separate from `SessionRecording` because only the sync queue has any
/// business reading a tombstone. The contract is deliberately conservative:
/// a tombstone is dropped only once the server confirms the forget, so a
/// failed request costs a repeated delete, not a resurrected session.
public protocol TombstoneStoring: Sendable {
    /// Ids deleted here that the server has not yet been told about.
    func tombstonedSessions() async -> [SessionRecord.ID]

    /// Drops the ids the server has confirmed it no longer holds.
    ///
    /// Called only after a successful `DeleteSessions`, and with exactly the
    /// ids that call carried — a wider drop would forget a deletion that never
    /// reached the server, and the next restore would hand the session back.
    func forgetTombstones(_ ids: [SessionRecord.ID]) async
}

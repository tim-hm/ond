import Foundation

/// How a session ends up: the vocabulary for where it is, and the one rule that
/// decides whether it happened at all.
///
/// Split from `SessionModel`'s own file, which drives the clock and the cues.
/// Nothing here reads the clock — `wasDiscarded` asks only what was recorded —
/// so the two topics share a type without having to share a file.
public extension SessionModel {
    enum Status: Sendable, Equatable {
        case ready
        case running
        /// Inside an open-ended hold, waiting on the person to say they are
        /// ready. The session is not paused: this is the technique working.
        case holding
        case paused
        /// Either outcome: the timeline ran out, or the person ended it. The
        /// distinction lives on `record.completed`.
        case finished
    }

    /// A session ended by hand inside this window never reaches the store: it
    /// is a false start — a mistap, a phone call — not practice, and a journal
    /// of two-second entries teaches people to stop trusting the journal.
    /// Completed sessions are exempt; finishing a plan is practice however
    /// short the plan was.
    static let minimumRecordedDuration: Duration = .seconds(10)

    /// Whether the ended session was let go rather than kept — the view's cue
    /// to close quietly instead of presenting a summary of nothing.
    var wasDiscarded: Bool {
        guard status == .finished, let record else { return false }
        return !record.completed && record.duration < Self.minimumRecordedDuration
    }
}

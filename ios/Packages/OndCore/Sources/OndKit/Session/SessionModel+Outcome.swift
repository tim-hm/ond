import Foundation

/// How a session ends up: the vocabulary for where it is, and the one rule
/// that decides whether it happened at all. Nothing here reads the clock —
/// `wasDiscarded` asks only what was recorded — so the two topics share a
/// type without having to share a file.
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

    /// Whether the ended session was let go rather than kept. The summary is
    /// shown either way — an ending nobody was told about reads as a crash —
    /// and this decides which of its forms. The rule itself lives on
    /// `SessionRecord.isFalseStart`, shared with the discreet model.
    var wasDiscarded: Bool {
        status == .finished && record?.isFalseStart == true
    }
}

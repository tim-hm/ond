import OndKit
import OndUI
import SwiftUI

/// What the dial holds.
///
/// The first round put every kind of stop in one scroll — a single
/// recommendation, the named moments, a progression and the whole catalogue —
/// and captioned which was which as the dial ticked past the boundaries. Four
/// kinds in one list is three too many, and a heading that changes while you
/// move makes the ground feel like it is moving too. These are the two ways out
/// that do not amount to dropping the caption and leaving a wall of stops.
enum DialContents {
    /// Only what the routing layer put there: the lead, the other named
    /// moments, the rungs of Start here. One kind of thing — a reason to breathe
    /// now — so nothing has to be captioned. The catalogue is not on the dial,
    /// because it is a whole tab of its own two icons away.
    case reasons

    /// All three sets, but never more than one at a time, chosen from a row of
    /// words that sits still while the dial moves. The reader still holds one
    /// kind of thing; the ground under it no longer changes by itself.
    case sets
}

/// Where the focused stop's own sentence is drawn.
///
/// Tim liked the sentence and not where it was: below the dial, it rendered
/// under the *next*, unfocused stop, so "steady the nerves" read as belonging to
/// "after a hard meeting". Both answers here fix that by attachment rather than
/// by spacing.
enum DialExplanation {
    /// Inside the window, directly under the focused title. Attachment is
    /// structural — the sentence is part of the row, so there is no arrangement
    /// of the screen in which it can belong to another one.
    case inWindow

    /// On the begin control, as what pressing it will do. The sentence leaves
    /// the list entirely and joins the commitment, which is the other honest
    /// place for it: not "what this row is" but "what happens next".
    case onBegin
}

/// The takes on the dial that are still open, switchable in place.
///
/// Aperture won the first round, the orb lost it, and both of those are settled
/// in the code rather than offered here. What is left are the two questions that
/// round did not answer, and the three cases are a 2×2 with the fourth corner
/// left out — `sets` paired with `onBegin` moves both variables at once and
/// would be the one comparison that says nothing.
///
/// Prototype scaffolding: two of these go, and the switch with them.
enum HomeDialOption: String, PrototypeChoice {
    /// The short dial, explained in the window. The most minimal answer to both
    /// questions.
    case few

    /// Every set reachable, explained in the window. Differs from `few` only in
    /// what the dial holds, so the pair isolates that question.
    case sets

    /// The short dial, explained on the begin control. Differs from `few` only
    /// in where the sentence lives, so that pair isolates the other one.
    case promise

    var contents: DialContents {
        switch self {
        case .few, .promise: .reasons
        case .sets: .sets
        }
    }

    var explanation: DialExplanation {
        switch self {
        case .few, .sets: .inWindow
        case .promise: .onBegin
        }
    }
}

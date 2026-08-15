import Foundation

/// The buffer between the stream's cadence and a reader's.
///
/// The server forwards the model's deltas one for one, so a reply arrives as
/// twenty to forty republishes a second at whatever rhythm the model happened
/// to have, each one a hard cut. This holds what has arrived and hands back a
/// little at a time, on a regular twelve a second — which is both a redraw
/// budget the transcript can afford and a growth the scroll beneath it can be
/// reasoned about.
///
/// It smooths the stream rather than slowing it. Each tick releases a share of
/// whatever is unrevealed, so the backlog settles where that share equals what
/// is arriving — about six words behind — and drains in well under a second
/// once the stream closes. A fixed words-per-second instead would leave a
/// two-hundred-word answer still writing itself half a minute after it had all
/// arrived, which is a reply the person is waiting on rather than reading.
///
/// A value type with no clock and no task of its own: everything here is a
/// function of what has arrived and how much of it is showing, which is what
/// makes the pacing assertable at all in a package whose views are structurally
/// untestable. ``CoachChatModel`` owns the loop that drives it.
struct RevealPacer {
    /// How often the reveal publishes, and therefore the whole of what caps the
    /// transcript's redraw rate. Also the window a view animates one step over,
    /// which is what turns twelve publishes a second into a reveal at the
    /// display's own rate.
    static let tick: Duration = .milliseconds(80)

    /// What share of the unrevealed backlog one tick releases.
    private static let chase = 0.25

    /// The most one tick releases, in characters.
    ///
    /// Only ever binds on the rule-based fallback, which answers in a single
    /// chunk: a quarter of a whole reply in one frame is the wall of text the
    /// pacing exists to avoid.
    private static let burst = 48

    private var arrived: [Character] = []
    private var revealableCount = 0
    private var revealedCount = 0
    private var isClosed = false

    /// What the transcript shows — always a prefix of what arrived, and always
    /// a whole number of words.
    private(set) var revealed = ""

    mutating func append(_ text: String) {
        for character in text {
            arrived.append(character)
            if character.isWhitespace {
                revealableCount = arrived.count
            }
        }
        if isClosed {
            revealableCount = arrived.count
        }
    }

    /// Marks the stream finished, which is what makes the last word revealable:
    /// until then the tail may be half a word the next chunk completes, and
    /// "mech" becoming "mechanism" is a stutter nobody asked to read.
    mutating func close() {
        isClosed = true
        revealableCount = arrived.count
    }

    /// Whether the reply is wholly on screen and nothing more is coming — the
    /// condition that ends the loop, releases the offer, and drops `isReplying`.
    var isSettled: Bool {
        isClosed && revealedCount == arrived.count
    }

    /// Everything at once, for the one path where nobody is watching the pace:
    /// cancel. What reaches the store should be what the server said, not what a
    /// presentation choice had got round to drawing.
    mutating func flush() {
        isClosed = true
        revealed.append(contentsOf: arrived[revealedCount...])
        revealedCount = arrived.count
        revealableCount = arrived.count
    }

    /// Releases one tick's worth, snapped forward to the end of a word.
    mutating func release() {
        let ceiling = revealableCount
        guard revealedCount < ceiling else { return }

        let step = max(
            1,
            min(Self.burst, Int(Double(ceiling - revealedCount) * Self.chase))
        )
        reveal(through: min(revealedCount + step, ceiling), upTo: ceiling)
    }

    /// Advances from the retained reveal offset to the first word boundary at
    /// or after `target`, or to `ceiling`.
    ///
    /// Each character between the stream and transcript is traversed once: the
    /// arrived count advances over new chunks in `append(_:)`, and this cursor
    /// advances only over the newly revealed slice.
    private mutating func reveal(through target: Int, upTo ceiling: Int) {
        var reached = revealedCount
        while reached < ceiling {
            let character = arrived[reached]
            reached += 1
            if reached >= target, character.isWhitespace {
                break
            }
        }

        revealed.append(contentsOf: arrived[revealedCount ..< reached])
        revealedCount = reached
    }
}

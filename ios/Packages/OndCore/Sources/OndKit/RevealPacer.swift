import Foundation

/// The buffer between the stream's cadence and a reader's: the server forwards
/// the model's deltas one for one, and this hands them back at a steady twelve a
/// second the transcript can afford to redraw. Each tick releases a share of the
/// backlog — it settles about six words behind and drains fast at close, where a
/// fixed rate would write for half a minute more. ``CoachChatModel`` owns the loop.
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
    /// or after `target`, or to `ceiling`. Each character between the stream
    /// and transcript is traversed once: this cursor advances only over the
    /// newly revealed slice.
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

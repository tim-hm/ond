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
/// function of two counts, which is what makes the pacing assertable at all in
/// a package whose views are structurally untestable. ``CoachChatModel`` owns
/// the loop that drives it.
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

    private var arrived = ""
    private var revealedCount = 0
    private var isClosed = false

    /// What the transcript shows — always a prefix of what arrived, and always
    /// a whole number of words.
    private(set) var revealed = ""

    mutating func append(_ text: String) {
        arrived += text
    }

    /// Marks the stream finished, which is what makes the last word revealable:
    /// until then the tail may be half a word the next chunk completes, and
    /// "mech" becoming "mechanism" is a stutter nobody asked to read.
    mutating func close() {
        isClosed = true
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
        revealedCount = arrived.count
        revealed = arrived
    }

    /// Releases one tick's worth, snapped forward to the end of a word.
    mutating func release() {
        let ceiling = revealableCount
        guard revealedCount < ceiling else { return }

        let backlog = ceiling - revealedCount
        let step = max(1, min(Self.burst, Int(Double(backlog) * Self.chase)))
        revealedCount = wordBoundary(atOrAfter: min(revealedCount + step, ceiling), upTo: ceiling)
        revealed = String(arrived.prefix(revealedCount))
    }

    /// How much of what arrived may be shown: everything once the stream has
    /// closed, and otherwise up to the end of the last whole word. A reply with
    /// no whitespace in it at all therefore shows nothing until it finishes,
    /// which is the right answer for the one thing shaped like that — a URL.
    private var revealableCount: Int {
        guard !isClosed else { return arrived.count }
        guard let last = arrived.lastIndex(where: \.isWhitespace) else { return 0 }
        return arrived.distance(from: arrived.startIndex, to: arrived.index(after: last))
    }

    /// The first position at or after `index` that ends a word, or `ceiling`.
    ///
    /// Forward rather than back, which is what guarantees progress: snapping to
    /// the *previous* boundary can return the position the reveal is already at,
    /// and a tick that releases nothing on a stream still arriving is a reveal
    /// that has quietly stopped.
    private func wordBoundary(atOrAfter index: Int, upTo ceiling: Int) -> Int {
        guard index < ceiling else { return ceiling }

        var boundary = max(index, 1)
        var cursor = arrived.index(arrived.startIndex, offsetBy: boundary)
        while boundary < ceiling {
            if arrived[arrived.index(before: cursor)].isWhitespace {
                return boundary
            }
            cursor = arrived.index(after: cursor)
            boundary += 1
        }
        return ceiling
    }
}

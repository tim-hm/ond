import Foundation

/// The cards home deals, in the order it deals them, each carrying the reason it is
/// on offer.
///
/// The reason is the point, and it is what settles what Breathe is *for* now that
/// three screens can show an exercise. Exercises explains a technique to somebody
/// who came to read; the coach reasons about a person; home says why *this one,
/// now* — the hour suggested it, you breathed it yesterday, it is the next rung.
/// That sentence is the one thing only home can write, and a card carrying it is
/// more informative than one repeating the catalogue's summary while being less
/// of a duplicate.
///
/// The pins come out of recorded history rather than out of a favourites store,
/// because there is no such store and inventing one to try a layout would be the
/// experiment growing a schema. What somebody has actually breathed most, and
/// most recently, is the same information a star would have carried and nobody
/// has to curate it.
///
/// Pure, and handed `history` rather than reading it, for the reason `HomeDial`
/// is handed the hour: the order depends on what somebody has done, and a rule
/// about that has to be testable without having done it.
public struct HomeDeck: Sendable, Hashable {
    /// Why a card sits where it does, in precedence order — a stop qualifying for
    /// two takes the earlier.
    public enum Reason: Sendable, Hashable {
        /// The routing layer's own choice, which stays at the front of the deck.
        case suggested

        /// Starred by hand, and so ahead of everything the deck worked out itself.
        case starred

        /// The most recent thing breathed, and when it was breathed.
        case again(Date)

        /// Breathed this many times, and so the likeliest thing wanted again.
        case often(Int)

        /// A named moment.
        case moment

        /// A rung of Start here.
        case step

        /// An exercise this person wrote.
        case yours

        /// A catalogue entry standing for itself.
        case catalogue

        /// The reason as a card has room to say it.
        ///
        /// Here rather than in the view because two layouts now draw the same reason
        /// and the wording is the whole point of it — a deck saying "you breathed
        /// this yesterday" while a board said "recent" would be two screens
        /// disagreeing about why they were showing the same thing.
        ///
        /// The date is formatted relatively rather than counted: "yesterday" is what
        /// somebody would say, and it is the phrasing that still works when the
        /// answer is "3 days ago".
        public var phrase: String {
            switch self {
            case .suggested: "Suggested now"
            case .starred: "Starred"
            case let .again(when): "You breathed this \(when.formatted(.relative(presentation: .named)))"
            case let .often(count): "You've breathed this \(count) times"
            case .moment: "A moment"
            case .step: "In Start here"
            case .yours: "Yours"
            case .catalogue: "From the catalogue"
            }
        }

        /// Whether a card showing this reason offers a star at all.
        ///
        /// The suggestion does not, and that is not tidiness. A star's only effect is
        /// to move a card to the front of the deck; the suggestion is already there,
        /// so the control would be one that visibly does nothing — and the card would
        /// go on reading "suggested now" either way, which makes it a switch with no
        /// state anybody can see.
        ///
        /// The cost is that an exercise somebody starred cannot be *un*-starred on a
        /// day the hour happens to suggest it. The star is still recorded and its
        /// control comes back as soon as the suggestion moves on, which is the smaller
        /// of the two surprises.
        public var acceptsStar: Bool {
            self != .suggested
        }

        /// Whether a card has to spell this reason out, or already shows it without
        /// words.
        ///
        /// Only the star does not. A filled star and the word "Starred" on the same
        /// card are one fact twice, and the glyph is the one that is also a control —
        /// so it is the words that go.
        ///
        /// `phrase` and `brief` still answer for `.starred`, and that is not an
        /// oversight: this governs what a card *prints*, while VoiceOver reads a
        /// label rather than a corner, and "Coherent Breathing, Starred" is the one
        /// place the word is still carrying its weight.
        public var isSpelled: Bool {
            self != .starred
        }

        /// The same reason for a tile, which has one short line and no room to
        /// finish a sentence.
        public var brief: String {
            switch self {
            case .suggested: "Suggested"
            case .starred: "Starred"
            case .again: "Last time"
            // The count, where the sentence would only have said "often". A tile has
            // one short line and a number is the most that line can carry.
            case let .often(count): "\(count) times"
            case .moment: "A moment"
            case .step: "Start here"
            case .yours: "Yours"
            case .catalogue: "Exercise"
            }
        }
    }

    /// One card: a stop, and why it is in front of you.
    public struct Card: Sendable, Hashable, Identifiable {
        public let stop: DialStop
        public let reason: Reason

        /// The stop's own id, which is already unique across the dial and stays
        /// the deck's scroll position through a rebuild.
        public var id: DialStop.ID {
            stop.id
        }
    }

    /// How many sessions make an exercise familiar enough to pin. Two rather than
    /// one, so a single curious tap does not become a permanent fixture of the
    /// screen.
    public static let familiar = 2

    /// How many familiar exercises are pinned. The deck is swiped, so a third and
    /// fourth pin cost nothing to hold — but they push the routing layer's own
    /// bands past the first flick, and the recommendation is meant to be the
    /// screen's argument rather than a thing at the back.
    public static let pins = 2

    /// The cards, in swipe order, deduplicated. Empty exactly when `stops` is.
    public let cards: [Card]

    /// - Parameters:
    ///   - stops: what home has to offer, lead first — `HomeDial.routed`.
    ///   - history: every session recorded on this device, in any order.
    ///   - starred: the ids this person starred — `StarredStopStore.starred`. Ahead
    ///     of the derived pins because a star is the one thing here somebody said
    ///     out loud, and behind the lead because the lead is still the app's answer
    ///     to *now*, which a star made on a different day cannot be.
    public init(stops: [DialStop], history: [SessionRecord], starred: Set<DialStop.ID> = []) {
        let counts = history.reduce(into: [String: Int]()) { counts, record in
            counts[record.techniqueSlug, default: 0] += 1
        }
        let latest = history.max { $0.startedAt < $1.startedAt }

        var placed: Set<DialStop.ID> = []
        var deck: [Card] = []

        func place(_ stop: DialStop, because reason: Reason) {
            guard placed.insert(stop.id).inserted else { return }
            deck.append(Card(stop: stop, reason: reason))
        }

        if let lead = stops.first {
            place(lead, because: .suggested)
        }

        for stop in stops where starred.contains(stop.id) {
            place(stop, because: .starred)
        }

        let again = stops.first { $0.technique.slug == latest?.techniqueSlug }

        if let latest, let again {
            place(again, because: .again(latest.startedAt))
        }

        for stop in Self.familiar(among: stops, counts: counts) {
            place(stop, because: .often(counts[stop.technique.slug] ?? 0))
        }

        for stop in stops {
            place(stop, because: Self.kind(of: stop))
        }

        cards = deck
    }

    /// The most-breathed stops worth pinning, most first.
    ///
    /// Ties break on dial order rather than on slug or on whatever the dictionary
    /// happened to hold, so the deck a person opens twice in a row is the same
    /// deck both times.
    private static func familiar(among stops: [DialStop], counts: [String: Int]) -> [DialStop] {
        stops.enumerated()
            .filter { counts[$0.element.technique.slug, default: 0] >= familiar }
            .sorted { left, right in
                let mine = counts[left.element.technique.slug, default: 0]
                let theirs = counts[right.element.technique.slug, default: 0]
                return mine == theirs ? left.offset < right.offset : mine > theirs
            }
            .prefix(pins)
            .map(\.element)
    }

    /// What a stop is, for a card that has no better reason to give.
    private static func kind(of stop: DialStop) -> Reason {
        switch stop.origin {
        case .occasion: .moment
        case .step: .step
        case .technique: stop.band == .yours ? .yours : .catalogue
        }
    }
}

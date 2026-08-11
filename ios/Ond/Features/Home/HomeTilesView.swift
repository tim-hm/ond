import OndKit
import OndUI
import SwiftUI

/// Home as a shortlist of rows above a board of cards, tapped to start and starred to
/// keep.
///
/// There is no focus and no Begin: a card starts what it names, so committing is one
/// gesture rather than two. This won out over five other readings of the screen tried
/// on a real phone — a linear dial with an aperture, a rotary wheel with the groups on
/// a second ring, a swipeable deck, a chip row that asked how long you had, and a
/// single take-it-or-browse offer. What decided it was that a board answers "what
/// should I do now" and "what else is there" in one glance, where every other layout
/// answered one and made the other a gesture away.
///
/// Paged rather than capped, and horizontally. A vertical scroll view would cost
/// Breathe the large title the other three tab roots have — a large title collapses
/// against the nearest one — so the whole board is reachable and the six a page holds
/// are still six at a glance. `HomeView`'s doc comment holds that constraint.
///
/// **Two shapes, and the shape is the hierarchy.** What the hour suggested and what
/// somebody starred are the exercises this screen is actually arguing for, so they sit
/// above the board as rows — `HomePinnedRow` — and only the rest are tiles. A square
/// card says "here are six things, compare them", which is the wrong sentence for a
/// shortlist of one or two; a row says "this one, and here it is". Neither loses
/// anything: a row carries the same reason, silhouette, length and star a tile does.
///
/// The suggestion is a row rather than the biggest card on the screen, which is a
/// deliberate bet and the part most likely to be wrong. Prominence comes from position
/// — first, above everything — rather than from area, on the argument that a person
/// who opened this app already means to breathe and needs the offer *reachable* more
/// than they need it *large*.
///
/// The star is the one thing here somebody curates, and it is a separate button
/// rather than part of the card: a long-press menu hides a feature behind a gesture
/// nobody discovers, and making the card itself a toggle would take away the tap
/// that starts it — the point of the layout.
///
/// **What the colour means, and what it cannot.** A tile's wash is
/// `TechniqueGoal.accent` — calm settles, sleep is night, energy sparks — which is
/// the app's one colour vocabulary, shared with the session player, the watch and
/// the site's figures. It stays that, and it is deliberately not re-purposed into
/// something with better spread: a board that coloured by length or by recency
/// would make this the one screen where green means something else.
///
/// The honest consequence is that colour does almost no work here, and the reason is
/// upstream rather than in the palette: this board draws `HomeDial.routed(starring:)`,
/// and neither the seeded occasions nor the Start here progression names a single
/// `energy` or `focus` exercise. Of the nine stops routed here, five are `calm` and the
/// rest split between `sleep` and `reset` — so two of the five accents reach this board
/// only when somebody stars such an exercise from its own screen, which is now the one
/// way they can. The goal is written in words on the same card anyway. What tells
/// the cards apart is their words — name, goal, length. A small figure used to sit
/// beside them, and went for the reason the list row's went: at card size every
/// calm exercise's cycle is the same hump, so it read as identification and
/// delivered decoration. The one place a figure earns its space is the detail
/// screen, where it is big enough to be labelled and read.
struct HomeTilesView: View {
    let cards: [HomeDeck.Card]
    let tier: SubscriptionTier

    /// Whether turning a page is felt, which is the cue setting's to decide and not
    /// this view's — somebody who has asked for a silent app did not mean "except the
    /// board".
    let ticks: Bool

    let starred: Set<DialStop.ID>
    let star: (DialStop) -> Void
    let start: (DialStop) -> Void

    private static let columns = 2

    /// How many exercises may sit in the strip above the board.
    ///
    /// Four, because a shortlist longer than four is not one — and because the board
    /// has to survive: rows and tiles are competing for one screen's height, and with
    /// no cap a person who starred everything would be left with a strip and no board
    /// at all. A fifth star simply stays a tile, which is where it was.
    private static let strip = 4

    @ScaledMetric private var tile: CGFloat = 116

    @State private var position = ScrollPosition(idType: Int.self)

    var body: some View {
        // Both read once and handed down. `pinned` was read eight times per pass
        // and `pages` three — each `pages` read recomputing `pinned` twice more,
        // once for the row count and once inside `remaining` — so one layout pass
        // filtered the deck eight times and built three throwaway Sets. The work
        // is small; the 8× multiplier hidden behind two innocent property reads is
        // the part worth removing.
        let pinned = pinned
        let pages = pages

        return VStack(spacing: Theme.Spacing.standard) {
            if !pinned.isEmpty {
                strip(pinned)
            }

            board(pages)

            if pages.count > 1 {
                dots(pages)
            }
        }
    }

    /// The shortlist: whatever the hour suggested, then whatever has been starred.
    ///
    /// Padded itself rather than through the stack, because the board beneath insets
    /// its *container* instead — that is what leaves the next page peeking — and one
    /// padding over both would inset the pager twice.
    private func strip(_ pinned: [HomeDeck.Card]) -> some View {
        VStack(spacing: Theme.Spacing.close) {
            ForEach(pinned) { card in
                HomePinnedRow(
                    card: card,
                    tier: tier,
                    isStarred: starred.contains(card.stop.id),
                    star: { star(card.stop) },
                    start: { start(card.stop) }
                )
            }
        }
        .padding(.horizontal, Theme.Spacing.standard)
    }

    private func board(_ pages: [[HomeDeck.Card]]) -> some View {
        ScrollView(.horizontal) {
            // Top-aligned, because a last page holding two cards is shorter than a
            // full one — centred, its two tiles would float in the middle of the
            // board and read as a different screen rather than the end of this one.
            HStack(alignment: .top, spacing: Theme.Spacing.loose) {
                ForEach(Array(pages.enumerated()), id: \.offset) { number, page in
                    grid(page)
                        .containerRelativeFrame(.horizontal)
                        .id(number)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        .scrollPosition($position)
        .safeAreaPadding(.horizontal, Theme.Spacing.standard)
        .sensoryFeedback(.selection, trigger: shown) { _, _ in ticks }
    }

    private func grid(_ page: [HomeDeck.Card]) -> some View {
        Grid(
            horizontalSpacing: Theme.Spacing.standard,
            verticalSpacing: Theme.Spacing.standard
        ) {
            ForEach(Array(rows(of: page).enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(row) { card in
                        self.card(card)
                    }
                    // Keeps a lone tile on the last row half width rather than
                    // letting it stretch across, so the board stays a grid.
                    if row.count < Self.columns {
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    }
                }
            }
        }
    }

    /// One card: why it is here, what it is, what shape it is, how long, and pressing
    /// it is the whole commitment. The star sits over the top corner and answers for
    /// itself.
    private func card(_ card: HomeDeck.Card) -> some View {
        let stop = card.stop

        return ZStack(alignment: .topTrailing) {
            Button {
                start(stop)
            } label: {
                VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                    reason(card.reason)

                    Text(stop.title)
                        .font(.headline)
                        .foregroundStyle(Theme.Ink.primary)
                        .lineLimit(2, reservesSpace: true)

                    Spacer(minLength: 0)

                    meta(stop)
                }
                // Clear of the star, which floats over this corner and would
                // otherwise sit on the end of a two-line name.
                .padding(.trailing, Theme.Spacing.loose)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: tile)
                .padding(Theme.Spacing.standard)
                .background(
                    stop.goal.accent.opacity(0.12),
                    in: .rect(cornerRadius: Theme.Radius.card)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(stop.title), \(card.reason.phrase)")
            .accessibilityHint("Starts the session")

            if card.reason.acceptsStar {
                starButton(stop)
            }
        }
    }

    /// Why this tile is here — or the space where those words would have been.
    ///
    /// Hidden rather than dropped for a starred tile, which the filled star in the
    /// corner already accounts for. `hidden()` keeps the line's height, so six titles
    /// in a grid stay on six matching baselines instead of one riding fourteen points
    /// higher than the five beside it, and takes the words out of VoiceOver's way
    /// while it is at it.
    @ViewBuilder
    private func reason(_ reason: HomeDeck.Reason) -> some View {
        let label = Text(reason.brief)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.Ink.tertiary)
            .textCase(.uppercase)
            .lineLimit(1)

        if reason.isSpelled {
            label
        } else {
            label.hidden()
        }
    }

    private func meta(_ stop: DialStop) -> some View {
        HStack(spacing: Theme.Spacing.tight) {
            Text(stop.goal.intentObject)
            Text("·")
            Text(stop.duration.glanceable)

            // Two marks, and both are about what tapping will actually do: a lock opens
            // the paywall, a watch says only `OndWatch` can deliver this one quietly.
            // Stated before the tap rather than only after it — see `HomeView.begin`.
            if !stop.technique.isUnlocked(for: tier) {
                Image(systemName: "lock.fill")
                    .accessibilityHidden(true)
            }

            if stop.surface == .discreet {
                Image(systemName: "applewatch")
                    .accessibilityHidden(true)
            }
        }
        .font(.caption)
        .foregroundStyle(Theme.Ink.secondary)
        // Shrink rather than wrap. The silhouette shares this line, and the one
        // exercise whose length spells out — the sigh's 22 seconds — pushed the facts
        // onto a second line and the tile out of step with the five beside it.
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    /// The star, in a target big enough to hit. The glyph is small and the corner it
    /// sits in is smaller; the frame is what stops this being a control only a
    /// precise thumb can reach.
    private func starButton(_ stop: DialStop) -> some View {
        let isStarred = starred.contains(stop.id)

        return Button {
            star(stop)
        } label: {
            Image(systemName: isStarred ? "star.fill" : "star")
                .font(.footnote)
                .foregroundStyle(isStarred ? stop.goal.accent : Theme.Ink.tertiary)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isStarred ? "Unstar \(stop.title)" : "Star \(stop.title)")
    }

    /// Which page is showing. Falls back to the first, because a scroll position
    /// holds no view id until something has been scrolled.
    private var shown: Int {
        position.viewID(type: Int.self) ?? 0
    }

    private func dots(_ pages: [[HomeDeck.Card]]) -> some View {
        HStack(spacing: Theme.Spacing.close) {
            ForEach(pages.indices, id: \.self) { number in
                Circle()
                    .fill(number == shown ? Theme.Ink.secondary : Theme.Surface.line)
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityHidden(true)
    }

    /// What the strip holds: the hour's suggestion first, then the stars, in dial
    /// order — `HomeDeck` has already decided both, and re-sorting here would be a
    /// second opinion about an order that is settled.
    private var pinned: [HomeDeck.Card] {
        Array(cards.filter(\.reason.isShortlisted).prefix(Self.strip))
    }

    /// Everything the strip did not take.
    private var remaining: [HomeDeck.Card] {
        let shortlisted = Set(pinned.map(\.id))
        return cards.filter { !shortlisted.contains($0.id) }
    }

    /// How many rows of tiles are left once the strip has taken its share.
    ///
    /// Two numbers rather than one fixed page. The strip is a single row for anybody
    /// who has starred nothing, and a board permanently short enough to survive four
    /// rows would waste that space on every such screen — while a board that always
    /// wanted three rows would be pushed off the bottom by a long shortlist.
    private var boardRows: Int {
        pinned.count > 2 ? 2 : 3
    }

    private var pages: [[HomeDeck.Card]] {
        let size = Self.columns * boardRows
        let remaining = remaining

        return stride(from: 0, to: remaining.count, by: size).map { start in
            Array(remaining[start ..< min(start + size, remaining.count)])
        }
    }

    private func rows(of page: [HomeDeck.Card]) -> [[HomeDeck.Card]] {
        stride(from: 0, to: page.count, by: Self.columns).map { start in
            Array(page[start ..< min(start + Self.columns, page.count)])
        }
    }
}

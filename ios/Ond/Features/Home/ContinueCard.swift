import OndKit
import OndStyle
import OndUI
import SwiftUI

/// Home's one lead action: the breath already stirring, what it is, and the
/// way in.
///
/// It draws whatever `HomeShelf.Lead` chose — the last run where one still
/// resolves, the hour's suggestion otherwise — with the eyebrow saying which.
/// The two cards this replaces answered "what fits now" and "what can I
/// repeat" side by side and left the person to arbitrate; the shelf already
/// knows which of those a tap here should mean, so one card asks one question
/// and the shelf answers it.
///
/// The card wears the breath's own gradient — inhale falling to hold — rather
/// than a goal accent, because what it holds is a breath, not a goal: the
/// goal's one mark is the dot beside the facts, where every row puts it.
struct ContinueCard: View {
    let lead: HomeShelf.Lead
    let tier: SubscriptionTier
    let start: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Whether the card is actually on screen. The idle clock pauses when it
    /// is not — Home is the tab every launch lands on, and a 10fps loop under
    /// the starred shelf's fold would run for as long as the app is open.
    @State private var isOnScreen = true

    /// The spec's own radius — wider than `Theme.Radius.card` because this is
    /// the one hero surface on the screen, not another row.
    private static let radius: CGFloat = 28

    /// The idle clock's frame cap — `AmbientField`'s rate, for its reason: a
    /// slow ambient swell is drawn no better at display refresh than at ten
    /// frames, and this one only has to read as alive beside the title.
    private static let idleFrameInterval: Double = 1.0 / 10

    var body: some View {
        Button(action: start) {
            layout
                .padding(Theme.Spacing.standard)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(
                        colors: [
                            Theme.Breath.inhale.opacity(0.16),
                            Theme.Breath.hold.opacity(0.07),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: Self.radius)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Self.radius)
                        .strokeBorder(Theme.Surface.line, lineWidth: 0.5)
                )
                // The rounded shape, not the default rect: the card's corners
                // are not part of it, and a tap there must not start a session.
                .contentShape(RoundedRectangle(cornerRadius: Self.radius))
        }
        .buttonStyle(.plain)
        .onScrollVisibilityChange { isOnScreen = $0 }
        .accessibilityLabel("\(lead.eyebrow), \(lead.stop.spokenLabel(for: tier))")
        .accessibilityHint("Starts the session")
        .accessibilityIdentifier("continue-card")
    }

    /// One row ordinarily; a column at accessibility sizes, where the grid
    /// this card replaced also reflowed — the glyph and the play circle are
    /// ~130 fixed points that would otherwise squeeze the title to a sliver.
    /// The glyph goes rather than shrinks: it is decoration, and the words
    /// are the card.
    @ViewBuilder
    private var layout: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Theme.Spacing.standard) {
                words
                play
            }
        } else {
            HStack(spacing: Theme.Spacing.standard) {
                glyph
                words
                Spacer(minLength: Theme.Spacing.close)
                play
            }
        }
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.close) {
            Text(lead.eyebrow)
                .eyebrow()

            Text(lead.stop.title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.Ink.primary)

            StopFactsLine(stop: lead.stop, tier: tier)
        }
    }

    /// The shared geometry at card size, stirring on the module's one idle
    /// clock — the `AmbientOrb` idiom: one timeline, paused wherever motion
    /// is unwanted, with Reduce Motion holding the reference instant so the
    /// still frame is a breath mid-stir rather than an emptied one.
    private var glyph: some View {
        TimelineView(.animation(
            minimumInterval: Self.idleFrameInterval,
            paused: reduceMotion || !isOnScreen
        )) { context in
            BreathGlyph(
                side: 78,
                pose: .idle(
                    at: reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
                ),
                layers: .card
            )
        }
    }

    /// The way in, drawn as one: the card is the button, and this is its
    /// stated affordance rather than a second control.
    private var play: some View {
        Image(systemName: "play.fill")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(Theme.Surface.ground)
            .frame(width: 52, height: 52)
            .background(Theme.Ink.primary, in: Circle())
            .accessibilityHidden(true)
    }
}

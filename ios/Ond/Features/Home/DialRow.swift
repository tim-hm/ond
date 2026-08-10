import OndKit
import OndStyle
import OndUI
import SwiftUI

/// One stop as the dial draws it: what it is called, what it is for, how long it
/// takes, and the sentence that only the stop in focus gets to say.
///
/// Its own file rather than a set of methods on `DialPicker` because the two
/// answer different questions. The picker owns where the column sits and which
/// detent the finger left it on; this owns what a stop looks like once it is
/// there — and the picker's own file, once the wheel's physics had to be written
/// out by hand rather than inherited from a `ScrollView`, no longer had room for
/// both.
///
/// Tapping a neighbour spins to it; tapping the one in focus does nothing,
/// because the screen has exactly one committing control and it is the begin
/// button below.
struct DialRow: View {
    let stop: DialStop

    /// Whether this is the stop the dial is pointing at. Passed in rather than
    /// compared here, so the row has no opinion about where focus lives.
    let isFocused: Bool

    /// What this person has bought, so a stop whose exercise it does not open can
    /// be marked. Marked rather than hidden or disabled: an exercise you cannot
    /// reach yet is still worth knowing the app has.
    let tier: SubscriptionTier

    /// What a tap asks for. The spin itself belongs to the picker, which is the
    /// only thing that knows how a detent is animated.
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(spacing: 2) {
                Text(stop.title)
                    .font(.system(size: titleSize, weight: isFocused ? .semibold : .regular))
                    .foregroundStyle(isFocused ? tint : Theme.Ink.tertiary)
                    .lineLimit(1)

                meta
                    .lineLimit(1)

                // Laid out on every row and drawn on one, so the slots stay the
                // same height and the titles do not shift as the focus moves
                // between them. Under the dial instead, it rendered beneath the
                // next unfocused stop and read as that one's; part of the row,
                // there is no arrangement of the screen in which it can belong
                // to another.
                Text(stop.detail)
                    .font(.footnote)
                    .foregroundStyle(Theme.Ink.secondary)
                    .lineLimit(2, reservesSpace: true)
                    .opacity(isFocused ? 1 : 0)
                    .padding(.top, Theme.Spacing.tight)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spoken)
        .accessibilityAddTraits(isFocused ? [.isButton, .isSelected] : .isButton)
    }

    /// The line under the name: what it is for, how long it takes, and the two
    /// marks that change what pressing begin will do.
    private var meta: some View {
        HStack(spacing: Theme.Spacing.tight) {
            if stop.surface == .discreet {
                // The one word that says this session will not take the screen.
                // Spelled out rather than given a glyph: every other mark on
                // this row is a state, and this is a promise.
                Text("quietly")
                    .foregroundStyle(Theme.Ink.secondary)
                Text("·")
            }

            Text(stop.goal.intentObject)
            Text("·")
            Text(length(width: .abbreviated))

            if !stop.technique.isUnlocked(for: tier) {
                // The brand accent and the glyph the catalogue's lock already
                // uses, so one mark does not mean two things in two places.
                Image(systemName: "lock.fill")
                    .font(.system(size: metaSize * 0.9))
                    .foregroundStyle(Theme.Accent.brand)
                    .accessibilityHidden(true)
            }
        }
        .font(.system(size: metaSize))
        .foregroundStyle(isFocused ? Theme.Ink.secondary : Theme.Ink.tertiary)
    }

    /// How long this stop takes, abbreviated for the row and spelled out for
    /// VoiceOver.
    ///
    /// One unit, so a dose fitted to whole cycles reads "3 min" rather than
    /// "2 min, 56 secs": the dial is browsed at a glance, and the exact length
    /// is the session's to keep rather than this row's to promise to the second.
    ///
    /// One function for both widths because the two must agree. `spokenLength`,
    /// which the rest of the app uses, is built for a phase — it says "176
    /// seconds" where this row says "3 min", and a screen reader contradicting
    /// the screen is worse than either wording alone.
    private func length(width: Duration.UnitsFormatStyle.UnitWidth) -> String {
        stop.duration.formatted(.units(
            allowed: [.minutes, .seconds],
            width: width,
            maximumUnitCount: 1
        ))
    }

    /// What a focused stop is drawn in.
    ///
    /// A discreet occasion keeps the ink rather than taking its goal's accent,
    /// which is the whole of how the dial says the two "meeting" entries differ:
    /// they name the same technique at the same dose, and the one that promises
    /// to stay out of the way is the one that does not light the screen up. The
    /// restraint *is* the signal.
    private var tint: Color {
        stop.surface == .discreet ? Theme.Ink.primary : stop.goal.accent
    }

    /// What VoiceOver reads. Everything the row draws has to be spoken —
    /// "quietly" and the lock are both promises about what begin will do — and
    /// in the same words the row itself draws them in — the goal as `relax`
    /// rather than `Calm`, the length as the row's one unit, the sentence
    /// included because a reader who cannot glance at the dial has no other way
    /// to tell which stop it belongs to. A screen reader contradicting the
    /// screen is worse than either wording alone.
    private var spoken: String {
        var said = "\(stop.title), \(stop.goal.intentObject), \(length(width: .wide))"
        if stop.surface == .discreet {
            said += ", runs quietly"
        }
        if !stop.technique.isUnlocked(for: tier) {
            said += ", included with önd Plus"
        }
        if !stop.detail.isEmpty {
            said += ". \(stop.detail)"
        }
        return said
    }

    @ScaledMetric(relativeTo: .body) private var titleSize: CGFloat = 17
    @ScaledMetric(relativeTo: .caption) private var metaSize: CGFloat = 12
}

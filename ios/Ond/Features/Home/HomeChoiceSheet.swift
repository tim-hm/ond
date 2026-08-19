import OndKit
import OndStyle
import OndUI
import SwiftUI

/// The sheet under Home's line: three exercises, one length, and the way to
/// the rest.
///
/// Its detent is its own height — nothing under the fold, no drag to expand —
/// so that it is a correction to the button rather than a second screen. If a
/// fourth thing wants in, something leaves. Choosing a row or a length moves
/// the check and writes the choice; it does not dismiss, because somebody
/// comparing two exercises should not have to reopen the sheet between them.
///
/// The rows and the lengths are `HomeOffer`'s; this draws them and hands each
/// tap to `HomeChoiceStore`, which is what Home reads the next offer from.
struct HomeChoiceSheet: View {
    let offer: HomeOffer

    /// What the "All exercises" row does — Home's to decide, because it closes
    /// this sheet and then moves the tab, in that order.
    let openExercises: () -> Void

    @Environment(HomeChoiceStore.self) private var choice

    /// The content's measured height, which is the sheet's one detent. Starts
    /// at a plausible size so the first presentation is not a zero-height
    /// sheet growing into place, and re-measures with the type size, so the
    /// sheet grows when somebody's text does.
    @State private var height: CGFloat = 420

    /// The spec's radius for the one hero surface on a screen — wider than
    /// `Theme.Radius.card`, which is the band's low end.
    private static let radius: CGFloat = 28

    var body: some View {
        // A scroller the sheet ordinarily has nothing to scroll: the detent is
        // the content's own height, so this only comes alive at accessibility
        // sizes, where the system clamps the detent to the screen and the rows
        // would otherwise be cut off under the fold.
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.standard) {
                Text("Start with")
                    .eyebrow()
                    .accessibilityAddTraits(.isHeader)

                rows

                if offer.isFittable {
                    length
                }

                DoorCard(title: "All exercises", action: openExercises)
                    .accessibilityHint("Opens the Exercises tab")
                    .accessibilityIdentifier("all-exercises-row")
            }
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.top, Theme.Spacing.loose)
            .padding(.bottom, Theme.Spacing.standard)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        // One detent, its own content's height: nothing to drag open and
        // nothing under the fold. It re-measures with the type size, so the
        // sheet grows when somebody's text does — up to the screen, past
        // which the system clamps it and the scroller above takes over.
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.Surface.raised)
        .presentationCornerRadius(Self.radius)
    }

    /// The three exercises, hairline-separated on one surface, the chosen one
    /// raised. The goal's colour is the dot, and the rhythm under the name is
    /// what the row would play at this person's dials.
    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(Array(offer.rows.enumerated()), id: \.element.id) { index, stop in
                row(stop, isChosen: index == 0)

                if index < offer.rows.count - 1 {
                    Divider().overlay(Theme.Surface.line)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .strokeBorder(Theme.Surface.line, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
    }

    private func row(_ stop: DialStop, isChosen: Bool) -> some View {
        Button {
            choice.choose(slug: stop.technique.slug)
        } label: {
            HStack(spacing: Theme.Spacing.close + Theme.Spacing.tight) {
                Circle()
                    .fill(stop.goal.accent)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                    Text(stop.technique.name)
                        .font(.headline)
                        // The spec tracks row titles −1%; of 17pt.
                        .tracking(-0.17)
                        .foregroundStyle(Theme.Ink.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    // Wrapped rather than truncated: "4 in, 4 hold, 4 out, 4
                    // hold" outgrows the row's width at accessibility sizes,
                    // and the numbers are what the row is for.
                    Text(stop.dialled.rhythmLine)
                        .font(.subheadline)
                        .foregroundStyle(Theme.Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: Theme.Spacing.close)

                if isChosen {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Accent.brand)
                }
            }
            .padding(.horizontal, Theme.Spacing.standard)
            .padding(.vertical, Theme.Spacing.close + Theme.Spacing.tight)
            .frame(
                maxWidth: .infinity,
                minHeight: Theme.Metrics.minimumTapTarget,
                alignment: .leading
            )
            .background(isChosen ? Theme.Surface.raisedAlt : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(stop.technique.name), \(stop.dialled.rhythmLine)")
        .accessibilityAddTraits(isChosen ? [.isSelected] : [])
    }

    /// The length, in the spec's three numbers. Hidden for an exercise whose
    /// length is its shape — `HomeOffer.isFittable` — rather than shown
    /// disabled: three numbers that change nothing are three questions.
    private var length: some View {
        HStack(spacing: Theme.Spacing.close) {
            Text("Length")
                .font(.subheadline)
                .foregroundStyle(Theme.Ink.secondary)

            Spacer(minLength: Theme.Spacing.close)

            ForEach(HomeOffer.lengths, id: \.self) { minutes in
                let length = Duration.seconds(minutes * 60)
                FilterPill(
                    title: length.glanceable,
                    accent: Theme.Accent.brand,
                    isSelected: minutes == offer.minutes,
                    showsDot: false
                ) {
                    choice.choose(minutes: minutes, for: offer.lead.technique.slug)
                }
                .accessibilityLabel(length.spelled)
                .accessibilityIdentifier("home-length-\(minutes)")
            }
        }
    }
}

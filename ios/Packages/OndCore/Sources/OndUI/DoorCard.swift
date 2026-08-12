import SwiftUI

/// A card that leads somewhere: a title, a line of explanation, an optional
/// figure, and the chevron that says it is a way in.
///
/// Journey had three of these written out longhand — the pause test, the
/// leaderboards, and the name that opts you into them — differing only in
/// their words and whether a number sat on the right. The Coach tab's way into
/// the basics made a second feature of the same shape, which is what moved it
/// here.
///
/// **A door with no caption is drawn compact**: the title and the chevron on one
/// row, for the case two doors stand side by side and neither is the screen's
/// argument. The Coach tab is that case — its two pinned doors cost about 180
/// points above the first conversation, which on a short screen was the whole of
/// the room the conversations had. The caption is what goes, and it is what the
/// full card is *for*, so the titles then have to stand alone: that is a
/// constraint on the copy rather than something this type can enforce.
///
/// One type rather than a second one beside it. The compact form began as its
/// own file reproducing this shell, and had already drifted on the chevron's
/// weight before either had shipped.
public struct DoorCard<Destination: View>: View {
    let title: String
    /// The sentence under the title, or nil for the compact form.
    let caption: String?
    /// Shown on the right in the attending accent, where there is one. The
    /// personal best is the only current use.
    let value: String?
    @ViewBuilder let destination: () -> Destination

    public init(
        title: String,
        caption: String? = nil,
        value: String? = nil,
        @ViewBuilder destination: @escaping () -> Destination
    ) {
        self.title = title
        self.caption = caption
        self.value = value
        self.destination = destination
    }

    public var body: some View {
        NavigationLink(destination: destination) {
            HStack(spacing: Theme.Spacing.close) {
                VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                    Text(title)
                        .font(caption == nil ? .subheadline.weight(.semibold) : .headline)
                        .lineLimit(1)

                    if let caption {
                        Text(caption)
                            .font(.caption)
                            .foregroundStyle(Theme.Ink.tertiary)
                    }
                }

                Spacer(minLength: 0)

                if let value {
                    Text(value)
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.Accent.attend)
                }

                Image(systemName: "chevron.right")
                    .foregroundStyle(Theme.Ink.tertiary)
                    // The link already announces itself as a way in; the
                    // chevron only says the same thing to the eye.
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Theme.Spacing.standard)
            .padding(.vertical, caption == nil ? Theme.Spacing.close : Theme.Spacing.standard)
            .frame(maxWidth: .infinity)
            .background(Theme.Surface.raised, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        }
        // Plain, because the default link style tints the whole card in the
        // accent and the chevron is already saying it is tappable.
        .buttonStyle(.plain)
    }
}

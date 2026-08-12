import SwiftUI

/// A `DoorCard` at half the width and none of the caption — a title and the
/// chevron that says it is a way in.
///
/// For the case two doors stand side by side and neither is the screen's
/// argument. The Coach tab is the one: its two pinned doors cost about 180
/// points above the first conversation, which on a short screen was the whole of
/// the room the conversations had. Two-up they cost one row.
///
/// The caption is what goes, and it is what a full `DoorCard` is *for* — a
/// sentence explaining where the door leads. A pair of doors sharing one row has
/// no space for two sentences, and half a sentence each is worse than none: the
/// titles here have to stand alone, which is a constraint on the copy rather
/// than a thing this type can enforce.
public struct CompactDoorCard<Destination: View>: View {
    let title: String
    @ViewBuilder let destination: () -> Destination

    public init(title: String, @ViewBuilder destination: @escaping () -> Destination) {
        self.title = title
        self.destination = destination
    }

    public var body: some View {
        NavigationLink(destination: destination) {
            HStack(spacing: Theme.Spacing.close) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(Theme.Ink.tertiary)
                    // The link already announces itself as a way in; the
                    // chevron only says the same thing to the eye.
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Theme.Spacing.standard)
            .padding(.vertical, Theme.Spacing.close)
            .frame(maxWidth: .infinity)
            .background(Theme.Surface.raised, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        }
        // Plain, because the default link style tints the whole card in the
        // accent and the chevron is already saying it is tappable.
        .buttonStyle(.plain)
    }
}

#if os(iOS)
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
    ///
    /// **A door is a push or an action, never both.** Most doors name a
    /// destination and become a `NavigationLink`; a door whose other side no
    /// link can reach — Home's road to the Exercises *tab* — takes a closure
    /// instead and draws the same shell, because the chevron's promise is
    /// "this leads somewhere", not "this pushes".
    ///
    /// **The surface is the caller's**, as it is on `StartableStopCard`. A door
    /// standing on a screen is a card and states `glassCard(interactive: true)`;
    /// Home's last practice row is a door *inside* a card, and a card on a card
    /// is what a hand-copied shell was written here to avoid.
    public struct DoorCard<Destination: View>: View {
        /// Which side of the push-or-action split this door took.
        private enum Way {
            case push(() -> Destination)
            case act(() -> Void)
        }

        let title: String
        /// The sentence under the title, or nil for the compact form.
        let caption: String?
        /// Shown on the right in the attending accent, where there is one. The
        /// personal best is the only current use.
        let value: String?
        private let way: Way

        /// A door that pushes `destination` onto the enclosing stack — the
        /// ordinary form.
        public init(
            title: String,
            caption: String? = nil,
            value: String? = nil,
            @ViewBuilder destination: @escaping () -> Destination
        ) {
            self.title = title
            self.caption = caption
            self.value = value
            way = .push(destination)
        }

        /// A door that runs `action` instead of pushing — for the other side
        /// no `NavigationLink` can reach, like a tab. `Never` pins the
        /// destination type parameter this form has no destination to infer
        /// from.
        public init(
            title: String,
            caption: String? = nil,
            value: String? = nil,
            action: @escaping () -> Void
        ) where Destination == Never {
            self.title = title
            self.caption = caption
            self.value = value
            way = .act(action)
        }

        public var body: some View {
            Group {
                switch way {
                case let .push(destination):
                    NavigationLink(destination: destination) { shell }
                case let .act(action):
                    Button(action: action) { shell }
                }
            }
            // Plain, because the default link style tints the whole card in the
            // accent and the chevron is already saying it is tappable.
            .buttonStyle(.plain)
        }

        /// Everything the card shows, as one sentence — the label the element
        /// above carries, since ignoring the children means nothing under it
        /// speaks for itself any more.
        private var spoken: String {
            [title, value, caption].compactMap(\.self).joined(separator: ", ")
        }

        private var shell: some View {
            HStack(spacing: Theme.Spacing.close) {
                VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                    Text(title)
                        // A captionless door is one row in somebody else's
                        // card, and bolding it would out-shout the rows above;
                        // a captioned door is its own card and keeps a
                        // headline. The quieter ink is the same argument: the
                        // door is a way out, not one of the rows.
                        .font(caption == nil ? .body : .headline)
                        .foregroundStyle(caption == nil ? Theme.Ink.secondary : Theme.Ink.primary)
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
            .frame(minHeight: Theme.Metrics.minimumTapTarget)
            .padding(.horizontal, Theme.Spacing.standard)
            .padding(.vertical, caption == nil ? Theme.Spacing.close : Theme.Spacing.standard)
            .frame(maxWidth: .infinity)
            // Claimed, for the finger and for the audit alike. The card used to
            // draw its own glass, and the material was what gave this row a
            // shape to be touched and measured against; with the surface handed
            // to the caller there is nothing behind the text, so both the tap
            // region and the accessibility frame collapse onto the words.
            // `StartableStopCard` claims its region the same way.
            .contentShape([.interaction, .accessibility], Rectangle())
            // One element, spoken as one sentence, and — the whole reason it
            // is `.ignore` rather than `.combine` — sized to *this* view. A
            // combined element takes the union of its children's frames, so
            // the compact form announced a target 18 points tall inside a card
            // more than twice that, which the system's audit refuses and a
            // finger would too.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)
        }
    }
#endif

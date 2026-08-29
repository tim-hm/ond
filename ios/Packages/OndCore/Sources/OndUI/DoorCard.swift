#if os(iOS)
    import SwiftUI

    /// A card that leads somewhere: title, caption, optional value, and the
    /// chevron that says it is a way in. A captionless door draws compact, so
    /// its title must stand alone — a constraint on the copy, not one this
    /// type enforces. A door is a push or an action, never both. The surface is
    /// the caller's: on a screen state `glassCard(interactive: true)`; never a card on a sheet.
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
                        // Wrapping rather than one truncated line: a door's
                        // title is short, and at accessibility sizes the
                        // chevron's width is enough to cut "All exercises" in
                        // half — which the system's audit refuses, rightly.
                        .fixedSize(horizontal: false, vertical: true)

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
            // With the surface handed to the caller there is nothing behind
            // the text, so the tap region and the accessibility frame would
            // collapse onto the words; claim both, as `StartableStopCard` does.
            .contentShape([.interaction, .accessibility], Rectangle())
            // `.ignore` rather than `.combine`: a combined element takes the
            // union of its children's frames, so the compact form announced a
            // target 18 points tall inside a card twice that — the audit
            // refuses it, and a finger would too.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)
        }
    }
#endif

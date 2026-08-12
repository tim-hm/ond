import OndKit
import OndUI
import SwiftUI

/// The words beside the ring: what to do now, and what is being practised.
///
/// System inks rather than `Theme.Ink`, which is the one place this surface
/// departs from the app's palette on purpose. A Live Activity is drawn on the
/// lock screen's own material over whatever wallpaper is behind it, and the
/// app's inks are measured against `Theme.Surface`, a ground that is not there.
/// `.primary` and `.secondary` are the pair the system guarantees against its
/// own container. The accent stays where it is measurable — the cue's geometry.
struct SessionCueLabel: View {
    let attributes: SessionActivityAttributes
    let presence: SessionPresence

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            HStack(spacing: Theme.Spacing.close) {
                Text(presence.instruction)
                    .font(.title3.weight(.medium))
                // A retention has no end the plan can name, so the only honest
                // number is how long it has run. The system counts it up
                // locally, with no update from the app.
                if case let .holding(since) = presence.stance {
                    Text(since, style: .timer)
                        .font(.title3)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(presence.spokenInstruction), \(caption)")
        .accessibilityValue(held)
    }

    /// The retention's count as the element's value.
    ///
    /// `.ignore` above drops every child label, the system-counted timer among
    /// them — and during a hold that timer is the only live number the lock
    /// screen carries, on the one phase whose end nothing can name in advance.
    /// A value rather than part of the label because the label is what a
    /// retention is, and this is how far into it somebody is.
    ///
    /// Empty off a hold, which is where there is no such number to give.
    private var held: Text {
        guard case let .holding(since) = presence.stance else { return Text("") }
        return Text(since, style: .timer)
    }

    /// What is being practised, and the nostril where there is one to name —
    /// which is what makes alternate-nostril breathing followable from a lock
    /// screen at all.
    private var caption: String {
        guard let hint = presence.breath.passage?.hint else { return attributes.techniqueName }
        return "\(attributes.techniqueName) · \(hint)"
    }
}

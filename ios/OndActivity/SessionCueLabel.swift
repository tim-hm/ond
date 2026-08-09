import OndKit
import OndUI
import SwiftUI

/// The words beside the dot: what to do now, and what is being practised.
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
    }

    /// What is being practised, and the nostril where there is one to name —
    /// which is what makes alternate-nostril breathing followable from a lock
    /// screen at all.
    private var caption: String {
        guard let hint = presence.breath.passage?.hint else { return attributes.techniqueName }
        return "\(attributes.techniqueName) · \(hint)"
    }
}

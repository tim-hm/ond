import OndKit
import OndUI
import SwiftUI

/// The words beside the breath: what to do now, and what is being practised.
/// System inks rather than `Theme.Ink`, on purpose: the Island draws this
/// over its own container and the lock screen card forces its subtree dark,
/// so `.primary`/`.secondary` resolve to the pair the system guarantees
/// against dark chrome. The accent stays where it is measurable — the geometry.
struct SessionCueLabel: View {
    let attributes: SessionActivityAttributes
    let presence: SessionPresence

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            HStack(spacing: Theme.Spacing.close) {
                Text(presence.instruction)
                    .displaySerif(size: 28)
                // A retention has no end the plan can name, so the only honest
                // number is how long it has run. The system counts it up
                // locally, with no update from the app.
                if let since = presence.heldSince {
                    held(since)
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
        // `.ignore` above drops every child label, the drawn timer among them —
        // and during a hold that count is the only live number the lock screen
        // carries, on the one phase whose end nothing can name in advance. A
        // value rather than part of the label because the label is what a
        // retention is, and this is how far into it somebody is.
        .accessibilityValue(presence.heldSince.map(held) ?? Text(""))
    }

    /// The retention's count, drawn and spoken from one construction so the
    /// number on screen and the number read out cannot be styled apart.
    private func held(_ since: Date) -> Text {
        Text(since, style: .timer)
    }

    /// What is being practised, and how — the nostril, the shape, or which hold
    /// this is. The merge rule itself lives on `SessionPresence`, because this
    /// target has no test bundle to hold one in.
    private var caption: String {
        presence.caption(of: attributes.techniqueName)
    }
}

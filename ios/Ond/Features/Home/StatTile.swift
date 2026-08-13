import OndUI
import SwiftUI

/// One number and what it counts, on a raised card.
///
/// A number, a word, and nothing about what either means — which is why it can
/// live here at all: the tile knows it is showing "42 days" and not that a day
/// is a local calendar day carrying a session. Whatever folded the number says
/// that, beside where it folded it.
///
/// It was private to the Journey screen while there was one, and Home draws the
/// same three — so it moved with them rather than being written out a second
/// time. It stays beside them: one screen in one target draws a tile, which is
/// as far as the escalation rule lets it go.
struct StatTile: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(spacing: Theme.Spacing.tight) {
            Text(value, format: .number)
                .font(.title3.weight(.semibold).monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.Ink.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.standard)
        .background(Theme.Surface.raised, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        // Combined so VoiceOver reads "42 days" rather than stopping between the
        // number and the word it belongs to.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }
}

import SwiftUI

/// One number and what it counts, on a raised card.
///
/// A number, a word, and nothing about what either means — which is why it can
/// live here at all: the tile knows it is showing "42 days" and not that a day
/// is a local calendar day carrying a session. Whatever folded the number says
/// that, beside where it folded it.
///
/// It was private to the Journey screen while there was one. Home draws the same
/// three, and a second hand-written copy would be three tiles in a row disagreeing
/// about a corner radius.
public struct StatTile: View {
    let value: Int
    let label: String

    public init(value: Int, label: String) {
        self.value = value
        self.label = label
    }

    public var body: some View {
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

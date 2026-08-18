import OndKit
import OndStyle
import OndUI
import SwiftUI

/// One thing to breathe, as a card on the wrist: what it is called, how long it
/// takes, and a tap that starts it.
///
/// The first card on the front door is drawn as the breath itself — inhale
/// falling to hold, the same gradient the phone's continue card wears — and the
/// rest in a wash of ink. That is the whole of the hierarchy: on a screen this
/// size, "the one you probably want" has to be visible before anything is read,
/// and a second heading would be more type than the cards it sorted.
struct WristStopCard: View {
    let stop: DialStop

    /// Whether this is the card the door leads with. One per screen, and the
    /// caller's to decide — the shelf knows which stop is most recent and this
    /// view knows nothing about history.
    var leads = false

    let start: () -> Void

    /// The spec's wrist radius, tighter than the phone's card: a small screen
    /// full of soft corners loses the edges that separate one card from the
    /// next.
    private static let radius: CGFloat = 18

    var body: some View {
        Button(action: start) {
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                Text(stop.title)
                    .font(.caption)
                    .foregroundStyle(Theme.Ink.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(stop.duration.glanceable)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Ink.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.close)
            .background(background)
            .contentShape(RoundedRectangle(cornerRadius: Self.radius))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(stop.title), \(stop.duration.glanceable)")
        .accessibilityHint("Starts the session")
    }

    /// The filled shape rather than a bare style, so the two branches can be a
    /// gradient and a flat colour without either being erased to reach one
    /// `background(_:in:)`.
    @ViewBuilder
    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius)

        if leads {
            shape.fill(
                LinearGradient(
                    colors: [
                        Theme.Breath.inhale.opacity(0.28),
                        Theme.Breath.hold.opacity(0.12),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        } else {
            shape.fill(Theme.Ink.primary.opacity(0.08))
        }
    }
}

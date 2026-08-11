import OndUI
import SwiftUI

/// The coach thinking, in the row its answer will fill.
///
/// `AmbientBreath` shrunk to a full stop and set in a bubble's own shape: the
/// app already has one idiom for "alive, and not asking anything of you" — the
/// onboarding orb breathes on the same clock — and a three-dot bounce would be
/// a second one borrowed from a livelier register. Drawing it inside the
/// coach's bubble rather than beside it means the answer grows out of the shape
/// that was already there.
///
/// Thirty a second and paused under Reduce Motion for the orb's reasons — the
/// paused frame is a still dot, which is the whole of the accessible variant.
struct ThinkingDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let diameter: CGFloat = 8

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let breath = reduceMotion
                ? 1.0
                : AmbientBreath.fullness(at: context.date.timeIntervalSinceReferenceDate)

            Circle()
                .fill(Theme.Accent.brand.opacity(0.3 + 0.5 * breath))
                .frame(width: Self.diameter, height: Self.diameter)
                .scaleEffect(0.8 + 0.2 * breath)
        }
        // A bubble's horizontal insets, and enough vertical to stand an
        // eight-point dot at about the height one line of text would — so the
        // swap to the first words is a fill rather than a jump.
        .frame(width: Self.diameter, height: Self.diameter)
        .padding(.horizontal, Theme.Spacing.standard)
        .padding(.vertical, Theme.Spacing.close + 4)
        .background(Theme.Surface.raised, in: .rect(cornerRadius: Theme.Radius.card))
        // Announced rather than hidden, unlike the orb: this one is the only
        // thing on screen saying the question was heard.
        .accessibilityElement()
        .accessibilityLabel("The coach is answering")
    }
}

import OndUI
import SwiftUI

/// The coach thinking, in the row its answer will fill. `AmbientBreath`
/// shrunk to a full stop: the onboarding orb breathes on the same clock, and
/// a three-dot bounce would be a second idiom from a livelier register. Drawn
/// inside the coach's bubble so the answer grows out of the shape already
/// there; under Reduce Motion the paused frame is a still dot.
struct ThinkingDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let diameter: CGFloat = 8

    var body: some View {
        TimelineView(.animation(
            minimumInterval: Theme.Motion.restfulFrameInterval,
            paused: reduceMotion
        )) { context in
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

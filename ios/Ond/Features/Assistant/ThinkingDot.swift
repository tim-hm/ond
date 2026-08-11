import OndUI
import SwiftUI

/// The coach thinking, in the row its answer will fill.
///
/// `AmbientOrb`'s breath at `AmbientOrb`'s pace, shrunk to a full stop and set
/// in a bubble's own shape: the app already has one idiom for "alive, and not
/// asking anything of you", and a three-dot bounce would be a second one
/// borrowed from a livelier register. Drawing it inside the coach's bubble
/// rather than beside it means the answer grows out of the shape that was
/// already there.
///
/// Thirty a second and paused under Reduce Motion for the orb's reasons — the
/// paused frame is a still dot, which is the whole of the accessible variant.
struct ThinkingDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One breath, in seconds. The orb's, deliberately: two things breathing at
    /// different rates on one screen read as two clocks.
    private static let cycle = 3.0

    private static let diameter: CGFloat = 8

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let breath = reduceMotion
                ? 1.0
                : fullness(at: context.date.timeIntervalSinceReferenceDate)

            Circle()
                .fill(Theme.Accent.brand.opacity(0.3 + 0.5 * breath))
                .frame(width: Self.diameter, height: Self.diameter)
                .scaleEffect(0.8 + 0.2 * breath)
        }
        // A real bubble's insets, so the row it stands in is the height the
        // answer will start at and the swap is a fill rather than a jump.
        .frame(width: Self.diameter, height: Self.diameter)
        .padding(.horizontal, Theme.Spacing.standard)
        .padding(.vertical, Theme.Spacing.close + 4)
        .background(Theme.Surface.raised, in: .rect(cornerRadius: Theme.Radius.card))
        // Announced rather than hidden, unlike the orb: this one is the only
        // thing on screen saying the question was heard.
        .accessibilityElement()
        .accessibilityLabel("The coach is answering")
    }

    /// How full the lungs are, 0...1, on the orb's cosine so the turn at each
    /// end is soft.
    private func fullness(at time: TimeInterval) -> Double {
        let progress = time.truncatingRemainder(dividingBy: Self.cycle) / Self.cycle
        return 0.5 - 0.5 * cos(progress * 2 * .pi)
    }
}

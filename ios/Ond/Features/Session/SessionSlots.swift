import OndUI
import SwiftUI

/// The three lines under the orb: what to do, how to do it, and how long is
/// left. Every slot keeps its height whether or not it has anything to say, so
/// a phase without a qualifier does not lift the count into its place. Phases
/// crossfade where they stand — nothing slides and nothing flips.
struct SessionSlots: View {
    /// The Action slot's word, already resolved: a paused session says so here.
    let action: String
    let qualifier: Qualifier?
    let count: Count?

    /// A qualifier and the accent it wears. A pair rather than two properties:
    /// the accent and the dot belong to a line that names a side, and a phase
    /// that names none may not reach for either.
    struct Qualifier: Equatable {
        let line: String
        /// The session's accent where the line names a side, nil otherwise.
        let accent: Color?
    }

    /// A count and how present it is, 0...1. Presence rather than a flag: the
    /// count fades across a hold's boundary instead of appearing at it.
    struct Count {
        let text: String
        let presence: Double
    }

    /// The refresh spec's reserved heights. Fixed rather than scaled — holding
    /// them is what lets a phase crossfade in place. The caller bounds Dynamic
    /// Type so the words still sit inside them; drawn unbounded, they spill.
    /// `SessionSummaryView` stands its own three lines in these, so the last
    /// screen of a session cannot fork from the session.
    static let actionHeight: CGFloat = 50
    static let qualifierHeight: CGFloat = 26
    static let countHeight: CGFloat = 22

    static let actionSize: CGFloat = 49
    private static let countSize: CGFloat = 14
    private static let dotSize: CGFloat = 6

    /// How long a phase takes to hand over. The words share the tint's own
    /// crossfade, so a boundary reads as one change rather than three.
    private static let crossfade = 0.4

    /// How long the count's presence takes to travel — the second it is
    /// sampled on, so the tween covers the gap between samples.
    private static let countStep = 1.0

    var body: some View {
        VStack(spacing: 0) {
            Text(action)
                .displaySerif(size: Self.actionSize)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: Self.crossfade), value: action)
                .frame(height: Self.actionHeight)

            qualifierLine
                .frame(height: Self.qualifierHeight)
                .animation(.easeInOut(duration: Self.crossfade), value: qualifier)

            countLine
                .frame(height: Self.countHeight)
        }
        .multilineTextAlignment(.center)
    }

    /// How to do it. Neutral ink, unless the line names the side being
    /// breathed through — the one case that takes the accent, and the only
    /// thing on this screen wearing a dot.
    @ViewBuilder
    private var qualifierLine: some View {
        if let qualifier {
            HStack(spacing: Theme.Spacing.close) {
                if let accent = qualifier.accent {
                    Circle()
                        .fill(accent)
                        .frame(width: Self.dotSize, height: Self.dotSize)
                }
                Text(qualifier.line)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .font(.body)
            .foregroundStyle(qualifier.accent ?? Theme.Ink.secondary)
            .transition(.opacity)
        }
    }

    /// How long is left, faded by the hold's own crossfade. The presence is
    /// sampled a second at a time with the words and moved linearly between
    /// samples: the fade it rides is linear too, so the tween lands on it, and
    /// one numeral does not earn a second clock at frame rate.
    @ViewBuilder
    private var countLine: some View {
        if let count {
            Text(count.text)
                .displayNumeral(size: Self.countSize, design: .monospaced)
                .foregroundStyle(Theme.Ink.tertiary)
                .opacity(count.presence)
                .animation(.linear(duration: Self.countStep), value: count.presence)
        }
    }
}

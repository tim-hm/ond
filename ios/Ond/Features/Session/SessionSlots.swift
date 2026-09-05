import OndUI
import SwiftUI

/// Fixed slots prevent a missing qualifier from moving the count.
struct SessionSlots: View {
    /// The Action slot's word, already resolved: a paused session says so here.
    let action: String
    let qualifier: Qualifier?
    let count: Count?
    let isPaused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayed: Instruction
    @State private var instructionOpacity = 1.0

    private struct Instruction: Equatable {
        let action: String
        let qualifier: Qualifier?
        let isPaused: Bool
    }

    private struct Handoff: Equatable {
        let instruction: Instruction
        let reduceMotion: Bool
    }

    init(action: String, qualifier: Qualifier?, count: Count?, isPaused: Bool) {
        self.action = action
        self.qualifier = qualifier
        self.count = count
        self.isPaused = isPaused
        _displayed = State(initialValue: Instruction(
            action: action,
            qualifier: qualifier,
            isPaused: isPaused
        ))
    }

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

    /// SessionSummaryView shares these heights. SessionWords uses a growing
    /// layout for accessibility text sizes.
    static let actionHeight: CGFloat = 50
    static let qualifierHeight: CGFloat = 26
    static let countHeight: CGFloat = 22

    static let actionSize: CGFloat = 49
    private static let countSize: CGFloat = 14
    private static let dotSize: CGFloat = 6

    /// How long the count's presence takes to travel — the second it is
    /// sampled on, so the tween covers the gap between samples.
    private static let countStep = 1.0

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                Text(displayed.action)
                    .displaySerif(size: Self.actionSize)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.identity)
                    .frame(height: Self.actionHeight)

                qualifierLine
                    .frame(height: Self.qualifierHeight)
            }
            .opacity(instructionOpacity)
            .task(id: Handoff(instruction: instruction, reduceMotion: reduceMotion)) {
                await handOff()
            }

            countLine
                .frame(height: Self.countHeight)
        }
        .multilineTextAlignment(.center)
    }

    private var instruction: Instruction {
        Instruction(action: action, qualifier: qualifier, isPaused: isPaused)
    }

    private func handOff() async {
        let next = instruction
        guard !reduceMotion, !next.isPaused, !displayed.isPaused, next != displayed else {
            replace(with: next, opacity: 1)
            return
        }

        withAnimation(.easeOut(duration: 0.08)) {
            instructionOpacity = 0
        }
        do {
            try await Task.sleep(for: .milliseconds(80))
        } catch {
            return
        }
        guard !Task.isCancelled else { return }

        // Replace both lines while invisible. Cancellation prevents an older
        // phase from replacing a newer instruction after pause or a fast step.
        replace(with: next, opacity: 0)
        withAnimation(.easeIn(duration: 0.14)) {
            instructionOpacity = 1
        }
    }

    private func replace(with instruction: Instruction, opacity: Double) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            displayed = instruction
            instructionOpacity = opacity
        }
    }

    /// How to do it. Neutral ink, unless the line names the side being
    /// breathed through — the one case that takes the accent, and the only
    /// thing on this screen wearing a dot.
    private var qualifierLine: some View {
        Color.clear.overlay {
            if let qualifier = displayed.qualifier {
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
            }
        }
        .transition(.identity)
    }

    /// How long is left, faded by the hold's own crossfade. The presence is
    /// sampled a second at a time with the words and moved linearly between
    /// samples: the fade it rides is linear too, so the tween lands on it, and
    /// one numeral does not earn a second clock at frame rate.
    private var countLine: some View {
        Color.clear.overlay {
            if let count {
                Text(count.text)
                    .displayNumeral(size: Self.countSize, design: .monospaced)
                    .foregroundStyle(Theme.Ink.tertiary)
                    .opacity(count.presence)
                    .animation(.linear(duration: Self.countStep), value: count.presence)
            }
        }
    }
}

import OndKit
import OndStyle
import OndUI
import SwiftUI

/// The phone's summary at wrist scale, on the phone's own strings. It reserves
/// no slot heights: this screen scrolls, so a late line extends the list rather
/// than pushing the figures, and three empty slots would spend a 40mm screen on
/// air. It has no mood check either — the wrist never asked the first half.
/// The cases are in docs/product/session-summary.md.
struct SessionSummaryView: View {
    /// Whether this session was kept, and what was kept. A session too short to
    /// record still comes here, with no figures under its two lines.
    let outcome: SessionSummaryLines.Outcome
    let technique: Technique

    /// Which words this session speaks, so the wrist and the phone end a
    /// playful session with the same sentence.
    let register: CopyRegister

    /// The stage this session earned, if it earned one. The wrist says the same
    /// sentence the phone does — a rung reached on the watch is reached, and
    /// hearing about it only on the phone later would make it the phone's.
    let reached: PracticeStage?

    let onDone: () -> Void

    private var note: String {
        SessionSummaryLines.note(for: outcome, exercise: technique.name, register: register)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.standard) {
                VStack(spacing: Theme.Spacing.tight) {
                    Text(SessionSummaryLines.headline(for: outcome, register: register))
                        .displaySerif(size: Theme.Metrics.wristDisplaySize)
                        .foregroundStyle(Theme.Ink.primary)

                    Text(note)
                        .font(.caption)
                        .foregroundStyle(Theme.Ink.secondary)

                    if let reached {
                        Text(reached.arrival)
                            .font(.caption2)
                            .foregroundStyle(Theme.Ink.secondary)
                            .transition(.opacity)
                    }
                }
                .multilineTextAlignment(.center)

                if let record = outcome.record {
                    figures(of: record)
                }

                Button("Done", action: onDone)
            }
            .padding(.vertical, Theme.Spacing.close)
            .animation(.easeIn(duration: 0.4), value: reached)
        }
    }

    /// A figure with a zero in it is absent rather than empty — the rule is
    /// `SessionSummaryLines.figures`, shared with the phone.
    private func figures(of record: SessionRecord) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.standard) {
            ForEach(SessionSummaryLines.figures(for: record)) { figure in
                VStack(spacing: Theme.Spacing.tight) {
                    Text(figure.value)
                        .font(.body.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(Theme.Ink.primary)

                    Text(figure.label)
                        .font(.caption2)
                        .foregroundStyle(Theme.Ink.secondary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

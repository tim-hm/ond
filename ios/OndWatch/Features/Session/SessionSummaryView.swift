import OndKit
import OndStyle
import OndUI
import SwiftUI

/// What you did, said once and warmly — the phone's summary at wrist size.
///
/// The copy rule from the business plan holds here more than anywhere: celebrate
/// what happened, never grade it. A session ended early is still a session.
struct SessionSummaryView: View {
    let record: SessionRecord
    let technique: Technique

    /// The stage this session earned, if it earned one. The wrist says the same
    /// sentence the phone does — a rung reached on the watch is reached, and
    /// hearing about it only on the phone later would make it the phone's.
    let reached: PracticeStage?

    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.standard) {
                Text(record.headline)
                    .font(.headline)
                    .foregroundStyle(Theme.Ink.primary)

                if let reached {
                    Text(reached.arrival)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.Ink.primary)
                        .transition(.opacity)
                }

                HStack(spacing: Theme.Spacing.standard) {
                    stat(record.cyclesLabel, "\(record.cyclesCompleted)")
                    stat("time", record.duration.formatted(.time(pattern: .minuteSecond)))
                    stat(record.breathsLabel, "\(record.breathCount)")
                }

                Button("Done", action: onDone)
            }
            .padding(.vertical, Theme.Spacing.close)
            .animation(.easeIn(duration: 0.4), value: reached)
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: Theme.Spacing.tight) {
            Text(value)
                .font(.body.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(Theme.Ink.primary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.Ink.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

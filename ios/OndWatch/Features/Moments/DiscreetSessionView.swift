import OndKit
import OndStyle
import OndUI
import SwiftUI

/// The discreet session's face: almost nothing, on purpose.
///
/// The session is the taps, and the taps are for a wrist that is down. This
/// screen exists for the two glances a discreet session actually gets — "is it
/// still going" on the way into the silence, and "how do I stop it" when the
/// meeting ends early — so it holds a timer, the burst count, and End. No
/// breathing shape: drawing one would invite watching a screen through a
/// session whose whole point is that there is nothing to watch.
struct DiscreetSessionView: View {
    @State private var model: DiscreetSessionModel
    @State private var runtime = WorkoutRuntime()

    /// The moment's name for the title — a string rather than the `Occasion`,
    /// so the one authoritative copy of the occasion is the slug already
    /// stamped into the model and no caller can pass a mismatched pair.
    private let occasionName: String
    /// Called once a finished session has been read and acknowledged — the
    /// wrist's chance to sync, hung off the same moment `SessionView` hangs
    /// its own.
    private let onFinished: () -> Void

    @Environment(\.dismiss) private var dismiss

    init(model: DiscreetSessionModel, occasionName: String, onFinished: @escaping () -> Void) {
        _model = State(wrappedValue: model)
        self.occasionName = occasionName
        self.onFinished = onFinished
    }

    var body: some View {
        Group {
            if model.status == .finished, let record = model.record, !model.wasDiscarded {
                SessionSummaryView(
                    record: record,
                    technique: model.technique,
                    reached: nil
                ) {
                    onFinished()
                    dismiss()
                }
            } else {
                face
            }
        }
        .containerBackground(
            model.technique.goal.accent.gradient.opacity(0.3),
            for: .navigation
        )
        .task {
            // The budget's release rides the model's own finish, not only the
            // view callbacks below: the normal posture is wrist down for half
            // an hour, and SwiftUI evaluates nothing while the screen is dark
            // — a workout released only by `.onChange` would outlive its
            // session until the wrist next came up.
            model.onFinished = { runtime.invalidate() }
            runtime.start()
            model.start()
        }
        .onDisappear {
            // Leaving the screen ends the session: unlike the guided player
            // there is no pause to come back to, and a cadence left running
            // headless would tap a wrist that thinks it stopped.
            model.end()
            runtime.invalidate()
        }
        .onChange(of: model.status) { _, status in
            guard status == .finished else { return }
            // The budget goes back when the cadence ends, not when the screen
            // does — a summary being read needs no workout session.
            runtime.invalidate()
            if model.wasDiscarded {
                dismiss()
            }
        }
    }

    private var face: some View {
        VStack(spacing: Theme.Spacing.close) {
            Text(occasionName)
                .font(.caption)
                .foregroundStyle(Theme.Ink.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            // Both lines under the one tick: `burstsBegun` is derived from the
            // clock, so outside a timeline it would never redraw.
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                VStack(spacing: Theme.Spacing.tight) {
                    Text(model.elapsed.formatted(.time(pattern: .minuteSecond)))
                        .font(.system(.title3, design: .rounded).weight(.light))
                        .monospacedDigit()
                        .foregroundStyle(Theme.Ink.primary)
                        .accessibilityLabel("Elapsed")

                    Text("burst \(model.burstsBegun) of \(model.totalBursts)")
                        .font(.caption2)
                        .foregroundStyle(Theme.Ink.secondary)
                }
            }

            Button("End", role: .destructive) {
                model.end()
            }
            .accessibilityHint("Ends the session and keeps what was breathed")
        }
    }
}

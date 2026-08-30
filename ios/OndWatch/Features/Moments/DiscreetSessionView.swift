import OndKit
import OndStyle
import OndUI
import SwiftUI

/// The discreet session's face: almost nothing, on purpose. The session is
/// the taps, for a wrist that is down, so this screen serves the two glances
/// it gets — "is it still going" and "how do I stop it" — with a timer, the
/// burst count, and End. No breathing shape: one would invite watching a
/// screen through a session whose point is that there is nothing to watch.
struct DiscreetSessionView: View {
    @State private var model: DiscreetSessionModel

    /// The moment's name for the title — a string rather than the `Occasion`,
    /// so the one authoritative copy of the occasion is the slug already
    /// stamped into the model and no caller can pass a mismatched pair.
    private let occasionName: String

    /// Called the instant the cadence ends, with whatever record it left —
    /// nil for a false start. At the end rather than on the summary's
    /// dismissal: the normal posture is wrist down for half an hour, and a
    /// sync that waited for a tap on Done would leave the phone with no
    /// session to show.
    private let onFinished: (SessionRecord?) -> Void

    @Environment(\.dismiss) private var dismiss

    /// The process's one workout budget. Read rather than injected: `start()`
    /// claims it from the launch handler that took it before any screen existed,
    /// and the system grants one workout session at a time, so there is nothing
    /// for a caller to choose.
    private var runtime: WorkoutRuntime {
        .shared
    }

    init(
        model: DiscreetSessionModel,
        occasionName: String,
        onFinished: @escaping (SessionRecord?) -> Void
    ) {
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
                    dismiss()
                }
            } else {
                face
            }
        }
        .wristGround(model.technique.goal.accent)
        .task {
            // Both hung on the model's own finish, not on the view callbacks
            // below: the normal posture is wrist down for half an hour, and
            // SwiftUI evaluates nothing while the screen is dark — a workout
            // released only by `.onChange`, or a sync started only by a tap on
            // Done, would wait for the wrist to come back up.
            model.onFinished = {
                runtime.invalidate()
                // Nil for a false start: nothing was stored, so a handler that
                // reports one would send the phone looking for a session that
                // exists nowhere. `DiscreetSessionModel` mints the record before
                // it decides to discard it, so the discard is what to ask.
                onFinished(model.wasDiscarded ? nil : model.record)
            }
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
            // A discarded false start has no summary worth showing, so the
            // screen goes rather than reporting a session nobody kept.
            guard status == .finished, model.wasDiscarded else { return }
            dismiss()
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
                let elapsed = model.elapsed.formatted(.time(pattern: .minuteSecond))

                VStack(spacing: Theme.Spacing.tight) {
                    Text(elapsed)
                        .font(.system(.title3, design: .rounded).weight(.light))
                        .monospacedDigit()
                        .foregroundStyle(Theme.Ink.primary)
                        // A label on a `Text` replaces what it says, so the
                        // count needs the value beside it — the guided hold
                        // does the same. This number is the only feedback
                        // that a mostly-silent half hour is still going.
                        .accessibilityLabel("Elapsed")
                        .accessibilityValue(elapsed)

                    Text("burst \(model.burstsBegun) of \(model.totalBursts)")
                        .font(.caption2)
                        .foregroundStyle(Theme.Ink.secondary)
                }
            }

            Button("End", role: .destructive) {
                model.end()
            }
            .accessibilityHint("Ends the session and records what you practised")
        }
    }
}

import OndKit
import OndStyle
import OndUI
import SwiftUI

/// What the wrist shows while it is lending its sensor to a session running on
/// the phone.
///
/// Not a session: there is no cadence, nothing to record, and nothing to write to
/// Health. The person is breathing to their phone and this screen is the receipt —
/// it says which arrangement the wrist is in, what it is measuring, and how to
/// stop. The number is here for the same reason the receipt is: a wrist that took
/// a workout budget without saying what for reads as a bug.
///
/// It draws and nothing else. The sensor loop, the pacing, the three ways sharing
/// ends and the workout budget all belong to `PulseRelay`, because the posture this
/// feature is used in is a wrist that is down — and SwiftUI evaluates nothing while
/// the screen is dark, so anything hung on a view update here would wait for
/// somebody to raise their arm. `DiscreetSessionView` carries the same finding.
struct PulseShareView: View {
    @State private var relay: PulseRelay

    @Environment(\.dismiss) private var dismiss

    init(relay: PulseRelay) {
        _relay = State(wrappedValue: relay)
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.close) {
            Text("Sharing with iPhone")
                .font(.caption)
                .foregroundStyle(Theme.Ink.secondary)
                .multilineTextAlignment(.center)

            Label {
                Text(rate)
                    .font(.system(.title2, design: .rounded).weight(.light))
                    .monospacedDigit()
            } icon: {
                Image(systemName: "heart.fill")
                    .foregroundStyle(Theme.Accent.brand)
            }
            .foregroundStyle(Theme.Ink.primary)
            .accessibilityLabel(readingDescription)

            Button("Stop", role: .destructive) {
                relay.stop()
            }
            .accessibilityHint("Stops sharing your heart rate with your iPhone")
        }
        .wristGround(Theme.Accent.brand)
        .task {
            // Both hung on the relay's own finish rather than on this screen: the
            // budget has to come back whether or not there is anybody looking at
            // the watch, which is most of this arrangement's life.
            relay.onFinished = {
                WorkoutRuntime.shared.invalidate()
            }
            // Claimed before the readings start, because the workout is what makes
            // the sensor sample every few seconds instead of every few minutes.
            WorkoutRuntime.shared.start()
            relay.start()
        }
        .onDisappear {
            // The one ending the relay cannot see: somebody swiped this away.
            relay.stop()
        }
        // The phone said it was done, the minute of silence ran out, or Stop was
        // tapped. The screen goes, and the sheet's own binding frees the wrist to
        // be asked again; the workout is already back by the time this runs.
        .onChange(of: relay.hasFinished) { _, hasFinished in
            guard hasFinished else { return }
            dismiss()
        }
    }

    /// The reading, or an em dash while there is none — the first seconds of
    /// every arrangement, and the whole of one on a wrist nobody is wearing.
    private var rate: String {
        relay.beatsPerMinute.map(String.init) ?? "—"
    }

    private var readingDescription: String {
        relay.beatsPerMinute.map { "\($0) beats per minute" } ?? "Waiting for a reading"
    }
}

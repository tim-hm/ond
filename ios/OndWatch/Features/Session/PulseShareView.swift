import OndKit
import OndStyle
import OndUI
import SwiftUI

/// What the wrist shows while lending its sensor to a session on the phone.
/// Not a session — no cadence, nothing recorded — just the receipt: what is
/// measured and how to stop, so a wrist holding a workout budget does not
/// read as a bug. It only draws: the sensor loop, pacing, endings and budget
/// belong to `PulseRelay`, since SwiftUI evaluates nothing while the screen is dark.
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

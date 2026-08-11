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
struct PulseShareView: View {
    @State private var relay: PulseRelay

    /// Where the readings come from. The seam rather than HealthKit: this screen
    /// is the only caller, and the loop below is two lines because everything
    /// interesting about the sharing lives in `PulseRelay`.
    private let health: any HealthStore

    @Environment(\.dismiss) private var dismiss

    /// The process's one workout budget, on `DiscreetSessionView`'s reasoning.
    /// Claimed here because it is what makes the sensor sample continuously: with
    /// no workout session running, HealthKit has a reading every few minutes and
    /// a badge would sit empty.
    private var runtime: WorkoutRuntime {
        .shared
    }

    init(relay: PulseRelay, health: any HealthStore) {
        _relay = State(wrappedValue: relay)
        self.health = health
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
        .containerBackground(Theme.Accent.brand.gradient.opacity(0.3), for: .navigation)
        .task {
            runtime.start()
            // Before the readings, not after: the relay's own backstop is armed
            // here, and a wrist that never gets a reading — no grant, no sensor
            // contact — is exactly the case where nothing else would ever end
            // this. The stream then finishes on its own when the screen goes.
            relay.start()
            for await sample in await health.heartRate() {
                relay.report(sample.beatsPerMinute)
            }
        }
        .onDisappear {
            relay.stop()
            runtime.invalidate()
        }
        // The phone said it was done, the minute of silence ran out, or Stop was
        // tapped. One reaction to all three: the screen goes, which hands the
        // budget back above and — through the sheet's own binding — lets the
        // wrist be asked again.
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

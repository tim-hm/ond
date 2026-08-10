import OndKit
import OndUI
import SwiftUI

/// The breath before the breathing: a beat to settle before the plan's clock
/// starts. Three seconds, not a preference — long enough to put the phone
/// somewhere and soften the shoulders, short enough that nobody reaches for a
/// skip. Cancel is the opposite of a skip: not a way to breathe sooner but a
/// way out for whoever tapped Begin and thought better of it, who was
/// otherwise stuck riding the count into a session they no longer wanted.
struct CountdownView: View {
    /// Seconds left. The screen presenting this owns the count, because the same
    /// value decides whether this view or the player is on screen at all.
    let count: Int
    let onCancel: () -> Void

    @Environment(SessionSettings.self) private var settings

    var body: some View {
        VStack(spacing: Theme.Spacing.loose) {
            VStack(spacing: Theme.Spacing.loose) {
                VStack(spacing: Theme.Spacing.close) {
                    Text("Get comfortable")
                        .font(.title2.weight(.medium))
                    // No step down in tone: this is drawn over
                    // `accentGround(_:)`, where secondary ink measures 3.26:1
                    // at `.subheadline`.
                    Text("Starting in")
                        .font(.subheadline)
                }

                Text("\(count)")
                    .displayNumeral(size: 96, design: .rounded)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.easeInOut(duration: 0.3), value: count)
            }
            // `SessionView.runCountdown` announces each second for VoiceOver,
            // on the same beat the sighted see, so there is nothing here to
            // read. On the count alone — the cancel below must stay reachable.
            .accessibilityHidden(true)
            .sensoryFeedback(.impact(weight: .light), trigger: count) { _, _ in
                settings.cueMode.playsHaptics
            }

            Button("Cancel", action: onCancel)
                .font(.subheadline)
                .frame(minHeight: 44)
        }
        .foregroundStyle(Theme.Ink.primary)
    }
}

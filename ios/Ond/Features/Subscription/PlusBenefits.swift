import OndUI
import SwiftUI

/// What önd+ opens, in the person's terms — four lines, one per thing that
/// costs something to serve.
///
/// A view rather than a list of strings on each screen that draws it. The
/// paywall and onboarding's trial step make the same promise, and a second copy
/// is a second thing to keep true when a gate moves — which is exactly what
/// `SubscriptionTier`'s named levers exist to prevent one level down.
struct PlusBenefits: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.close) {
            ForEach(Self.lines, id: \.self) { line in
                Label(line, systemImage: "checkmark")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Ink.secondary)
                    .labelStyle(.titleAndIcon)
            }
        }
    }

    private static let lines = [
        "Your coach, answering from your own practice",
        "The leaderboards, globally and in your age band",
        "What your resting rate and HRV are doing",
        "Sessions sent to your watch, and its heart rate here",
    ]
}

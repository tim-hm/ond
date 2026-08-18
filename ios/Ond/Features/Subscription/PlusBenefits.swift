import OndUI
import SwiftUI

/// What önd+ opens, in the person's terms — four aligned lines, one per thing
/// that costs something to serve.
///
/// A view rather than a list of strings on each screen that draws it. The
/// paywall and onboarding's trial step make the same promise, and a second copy
/// is a second thing to keep true when a gate moves — which is exactly what
/// `SubscriptionTier`'s named levers exist to prevent one level down.
struct PlusBenefits: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.close) {
            ForEach(Self.benefits) { benefit in
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.standard) {
                    Image(systemName: benefit.systemImage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Accent.brand)
                        .frame(width: Theme.Spacing.loose)
                        .accessibilityHidden(true)

                    Text(benefit.title)
                        .font(.subheadline)
                        .foregroundStyle(Theme.Ink.secondary)
                }
            }
        }
    }

    private struct Benefit: Identifiable {
        let title: String
        let systemImage: String

        var id: String {
            title
        }
    }

    private static let benefits = [
        Benefit(
            title: "Coach informed by your goals and practice",
            systemImage: CoachGlyph.symbol
        ),
        Benefit(title: "Global and age-band leaderboards", systemImage: "trophy"),
        Benefit(
            title: "Breathing, heart-rate and HRV trends, and your heart around each practice",
            systemImage: "waveform.path.ecg"
        ),
        // Names the order rather than "connected Watch practice", which reads as
        // wrist sessions reaching your journey — free, and always was.
        Benefit(
            title: "Send a session to your Watch, with live heart rate",
            systemImage: "applewatch.radiowaves.left.and.right"
        ),
    ]
}

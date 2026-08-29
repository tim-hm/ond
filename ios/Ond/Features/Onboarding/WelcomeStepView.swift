import OndUI
import SwiftUI

/// The first screen: the orb already breathing, the name, and what the app is
/// for — four things, because its whole job is to make somebody want the next
/// one. The evidence stance it once carried here is not gone: the headline
/// claims only what evidence supports, and `Foundations` holds the detail.
/// Named outcomes — nobody downloads a breathing app wanting to breathe.
struct WelcomeStepView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Whether the welcome copy has floated in yet. Starts false so the screen
    /// arrives rather than being merely there. It replays deliberately: the
    /// flow gives each step its own identity, so Back rebuilds this view with
    /// a fresh `false` and the entrance runs again.
    @State private var hasArrived = false

    /// The wordmark's letter spacing, scaled with its own type. A fixed value
    /// beside a Dynamic Type font closes up as the letters grow, which turns a
    /// spaced wordmark into an ordinary word at exactly the sizes somebody
    /// asked for larger text.
    @ScaledMetric(relativeTo: .title2) private var wordmarkTracking: CGFloat = 3

    var body: some View {
        VStack(spacing: Theme.Spacing.loose) {
            AmbientOrb(accent: Theme.Accent.brand)

            VStack(spacing: Theme.Spacing.standard) {
                // Lowercase, and never uppercased: the name is önd, and ÖND is
                // a different word wearing its hat.
                Text("önd breathe")
                    .font(Theme.Typeface.wordmark(size: 22))
                    .tracking(wordmarkTracking)
                    .foregroundStyle(Theme.Ink.secondary)

                Text("Guided breathing, grounded in evidence.")
                    .displaySerif(size: 34)
                    .foregroundStyle(Theme.Ink.primary)

                Text("Fall asleep faster, steady yourself before something hard, "
                    + "and come down from a day that got away from you — with "
                    + "exercises drawn from what the research actually supports.")
                    .font(.body)
                    .foregroundStyle(Theme.Ink.secondary)
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity)
        // The one entrance in the app: everything rises to meet the orb, which
        // is already breathing when it arrives.
        .opacity(hasArrived ? 1 : 0)
        .offset(y: hasArrived || reduceMotion ? 0 : 12)
        .animation(.easeOut(duration: 0.8).delay(0.2), value: hasArrived)
        .onAppear { hasArrived = true }
    }
}

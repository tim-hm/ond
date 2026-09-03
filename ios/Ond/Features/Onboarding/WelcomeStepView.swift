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

    var body: some View {
        // `Spacer(minLength:)` rather than fixed gaps: the scroller stretches
        // this to the screen's height, and at accessibility sizes the spacers
        // meet their minimum and the screen scrolls instead of crushing.
        VStack(spacing: 0) {
            VStack(spacing: Theme.Spacing.standard) {
                Wordmark()

                Text("Guided breathing, grounded in evidence.")
                    .displaySerif(size: 39)
                    .foregroundStyle(Theme.Ink.primary)
                    // `centredInScroller` measures this stack at its ideal
                    // width, where the headline is one line. Without this it
                    // keeps that line and truncates at any screen width.
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            // Clear of the toolbar rather than tucked under it: the progress
            // dots and Skip are the flow's chrome, and the name is the first
            // thing this screen says.
            .padding(.top, Theme.Spacing.section)

            Spacer(minLength: Theme.Spacing.loose)

            AmbientOrb(accent: Theme.Accent.brand)

            Spacer(minLength: Theme.Spacing.loose)

            Text("Fall asleep faster, steady yourself before something hard, "
                + "and come down from a hard day, with exercises drawn from "
                + "what the research supports.")
                .font(.body)
                .foregroundStyle(Theme.Ink.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        // The one entrance in the app: everything rises to meet the orb, which
        // is already breathing when it arrives.
        .opacity(hasArrived ? 1 : 0)
        .offset(y: hasArrived || reduceMotion ? 0 : 12)
        .animation(.easeOut(duration: 0.8).delay(0.2), value: hasArrived)
        .onAppear { hasArrived = true }
    }
}

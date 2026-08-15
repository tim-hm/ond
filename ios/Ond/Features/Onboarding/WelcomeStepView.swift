import OndUI
import SwiftUI

/// The first screen: the orb already breathing, the name, and what the app is
/// for.
///
/// Four things and no more — orb, wordmark, headline, one paragraph — because
/// this screen's whole job is to make somebody want the next one. It used to
/// carry the evidence stance as three paragraphs in a card, which was the most
/// interesting true thing about the app said to a person who had not yet been
/// given a reason to care, and it ran past the fold. The stance is not gone: the
/// headline still claims only what evidence supports, `Foundations` carries the
/// detail, and every technique states its own limits where they apply. This
/// screen sells the reason to open the app; the honesty is kept everywhere the
/// claim is actually made.
///
/// Named outcomes rather than a description of the practice — sleep, nerves, a
/// day that got away — because nobody downloads a breathing app wanting to
/// breathe.
///
/// Centred where every question is leading-aligned: this screen is a greeting,
/// not a step, and the layout should say so.
struct WelcomeStepView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Whether the welcome copy has floated in yet. Starts false so the screen
    /// arrives rather than being merely there — the copy rising to meet the orb
    /// is what this screen is.
    ///
    /// It replays. Back from the first question lands here, and the flow gives
    /// each step its own identity so the steps can blur into one another — so
    /// this view is rebuilt with a fresh `false` and the entrance runs again.
    /// Left that way deliberately: somebody who came back to re-read the page
    /// gets the page as it is, and a screen that arrived once and then merely
    /// existed would be the odd one out on the way back.
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
                    .font(.system(.title2, design: .serif, weight: .medium))
                    .tracking(wordmarkTracking)
                    .foregroundStyle(Theme.Ink.secondary)

                Text("Guided breathing, grounded in evidence.")
                    .font(.largeTitle.weight(.medium))
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

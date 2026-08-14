import OndUI
import SwiftUI

/// The first screen: the orb already breathing, the name, and what this app
/// stands on.
///
/// The welcome and the evidence stance used to be two screens, and they are one
/// because they were making the same point twice — a greeting that says nothing
/// is a tap charged for nothing, and a stance nobody has been given a reason to
/// care about yet is a page to swipe past. Together, the app introduces itself
/// by saying what it will and will not claim, which is the most interesting true
/// thing about it.
///
/// A stance, not a bibliography: no figures, no citations, no trial names.
/// `Foundations` carries the detail for anyone who goes looking, and the footer
/// says where it is.
///
/// Centred where every question is leading-aligned — this screen is a greeting,
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
                Text("önd")
                    .font(.system(.title2, design: .serif, weight: .medium))
                    .tracking(wordmarkTracking)
                    .foregroundStyle(Theme.Ink.secondary)

                Text("Guided breathing, grounded in evidence.")
                    .font(.largeTitle.weight(.medium))
                    .foregroundStyle(Theme.Ink.primary)

                Text("A focused practice, with clear limits on what the research can claim.")
                    .font(.body)
                    .foregroundStyle(Theme.Ink.secondary)
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            stance

            Text("No invented scores or breath-hold contests. The Basics explains the "
                + "evidence and its limits whenever you want it.")
                .font(.footnote)
                .foregroundStyle(Theme.Ink.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        // The one entrance in the app: everything rises to meet the orb, which
        // is already breathing when it arrives.
        .opacity(hasArrived ? 1 : 0)
        .offset(y: hasArrived || reduceMotion ? 0 : 12)
        .animation(.easeOut(duration: 0.8).delay(0.2), value: hasArrived)
        .onAppear { hasArrived = true }
    }

    /// Three limits the rest of the app keeps: the reliable immediate effect,
    /// the uneven emotional evidence, and the absence of a proven best pattern
    /// or dose. Nothing after this screen has to oversell to make up for a
    /// promise made here.
    private var stance: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.standard) {
            Text("Slow breathing reliably changes heart-rate variability while you "
                + "practise. Effects on stress, mood and anxiety are promising, but "
                + "modest and uneven.")

            Text("No single pattern or pace has proved best. A quiet, comfortable "
                + "breath matters more than a perfect count.")

            Text("Short, regular practice is common in research, but the ideal dose "
                + "is not settled. Start with something you'll return to.")
        }
        .font(.callout)
        .foregroundStyle(Theme.Ink.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.standard)
        .glassCard()
    }
}

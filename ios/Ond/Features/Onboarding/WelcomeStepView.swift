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
    /// Nothing in the flow returns here: Back from the first question refuses,
    /// so this fires once per launch of the flow and never replays.
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

                Text("Driven by science, not pseudoscience.")
                    .font(.largeTitle.weight(.medium))
                    .foregroundStyle(Theme.Ink.primary)

                Text("Breathwork attracts a lot of noise. Here's the part that holds up.")
                    .font(.body)
                    .foregroundStyle(Theme.Ink.secondary)
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            stance

            Text("So there are no invented scores here, no breath-hold contests, and "
                + "nothing claimed that the research can't carry. Foundations has the "
                + "detail whenever you want it, and it's fine if you never do.")
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

    /// Four sentences, and every one of them is a limit on what the app will
    /// claim later: the effects are real and modest, they come from short
    /// regular sits, the pace does the work rather than the pattern, and part
    /// of it is simply stopping. Nothing after this screen has to oversell to
    /// make up for a promise made here.
    private var stance: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.standard) {
            Text("Slow breathing is one of the better-evidenced ways to settle "
                + "yourself. Trials find real improvements in stress, mood and "
                + "sleep — real, and modest.")

            Text("The gains come from short, regular sits. Around five minutes, "
                + "most days, over weeks — not from one heroic session.")

            Text("The pace is what does the work. The famous counts and clever "
                + "patterns are mostly comfort and preference, so pick the one "
                + "you'll come back to.")

            Text("And some of the effect is simply stopping and paying attention "
                + "for a few minutes. That isn't a loophole in the science — it's "
                + "part of how this works.")
        }
        .font(.callout)
        .foregroundStyle(Theme.Ink.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.standard)
        .glassCard()
    }
}

import OndUI
import SwiftUI

/// The app's thesis, stated before it asks anything.
///
/// Breathwork sells well, which is why most of what is claimed for it is not
/// evidenced and most of what is evidenced is unexciting. This screen says which
/// is which — including that the effects are modest and that the ritual is part
/// of them — so that nothing later in the app has to oversell to make up for it.
/// It is a stance, not a bibliography: no figures, no citations, no trial names.
/// `Foundations` carries the detail for anyone who goes looking.
struct EvidenceStepView: View {
    var body: some View {
        OnboardingQuestion(
            title: "What this actually does",
            subtitle: "Breathwork attracts a lot of noise. This is the part that holds up."
        ) {
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

            Text("So there are no invented scores here, no breath-hold contests, and "
                + "nothing claimed that the research can't carry. Foundations has the "
                + "detail whenever you want it, and it's fine if you never do.")
                .font(.footnote)
                .foregroundStyle(Theme.Ink.tertiary)
                .padding(.top, Theme.Spacing.close)
        }
    }
}

import OndKit
import OndUI
import SwiftUI

/// What Health has to say about this person's body, shown to the person it is
/// about.
///
/// Beside the two measurements they take themselves, and deliberately marked as
/// coming from somewhere else: a pause and a resting rate are counted on
/// purpose, these are read off a watch that was being worn anyway. The heading
/// carries that distinction so the screen never implies somebody sat down and
/// measured their HRV.
///
/// The sleeping breathing rate leads, because it is the passive companion to
/// the resting rate above it — the same quantity, measured overnight instead of
/// sitting still, and the one figure here that the practice is actually trying
/// to move. Its own label says "sleeping" every time it appears, for the reason
/// `CoachHealthContext.sleepingBreathingRate` gives: everybody breathes slower
/// asleep, so a person who read the two as one series would see progress they
/// did not make, or lose progress they did.
///
/// It exists because the opt-in had no observable effect. The switch lived
/// fifth of seven sections down Settings, nothing was ever drawn from it, and a
/// grant refused at Health's own sheet was indistinguishable from one that
/// worked — so somebody could leave it on for months, getting nothing, with no
/// way to find out. Showing the summary is the feedback; the empty state is the
/// rest of it.
///
/// Every figure keeps the discipline the server's briefing keeps: rounded
/// weekly means introduced by "about", trends stated against a baseline, and
/// never a number that reads like a reading somebody took.
///
/// At the app root rather than in a feature, on `StopRow`'s precedent: the
/// check-ins screen shows it in every state — the offer and the opt-in are
/// that screen's feedback loop — while Home mounts it only once there are
/// trends to draw, so each host decides which of its states exist on screen.
struct HealthTrendsCard: View {
    let health: HealthContextModel

    @Environment(SubscriptionStore.self) private var plus

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.standard) {
            Text("From your watch")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Ink.tertiary)
                .textCase(.uppercase)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.standard)
        // Not interactive: the card holds a control rather than being one, so
        // the glass must not flex when the control inside is what was touched.
        .glassCard()
        // Runs on every appearance rather than once: somebody who granted access
        // in the Health app between visits should find the numbers here, and
        // nothing else would tell this screen that changed. Not run at all
        // below the subscription — there is nothing on screen for it to fill,
        // and a Health read on behalf of a card showing an offer is a query
        // nobody asked for.
        //
        // Keyed on that answer rather than bare, so buying önd+ from the offer
        // this card is showing runs the read the guard just refused. Unkeyed, a
        // purchase in place would leave the card empty until the screen was
        // left and come back to.
        .task(id: isUnlocked) {
            guard isUnlocked else { return }
            await health.loadHealthTrends()
        }
    }

    private var isUnlocked: Bool {
        plus.tier >= .healthTrends
    }

    @ViewBuilder
    private var content: some View {
        if isUnlocked {
            unlocked
        } else {
            locked
        }
    }

    @ViewBuilder
    private var unlocked: some View {
        switch health.healthTrends {
        case .off:
            invitation
        case .loading:
            // No spinner: three Health queries against a local daemon are quick,
            // and a spinner that flashes for 80ms is noise rather than news.
            Text("Reading Health…")
                .font(.callout)
                .foregroundStyle(Theme.Ink.tertiary)
        case let .trends(context):
            trends(context)
        case .nothingReadable:
            nothingReadable
        }
    }

    /// The same invitation, with the price on it.
    ///
    /// It says what the numbers are *for* rather than listing them, because the
    /// figures themselves are not what önd+ sells — Apple's Health app shows
    /// anybody their own HRV for nothing. What is sold is the coach reasoning
    /// from them, which is a briefing attached to a model call.
    private var locked: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.close) {
            Text(
                "If you wear an Apple Watch overnight, önd+ can add weekly sleeping "
                    + "breathing rate, resting heart rate and HRV trends to your coach's context."
            )
            .font(.callout)
            .foregroundStyle(Theme.Ink.secondary)

            UpgradePrompt(reason: "Reading your trends is part of", for: .health)
        }
    }

    /// The opt-in, offered where the data would appear rather than only in
    /// Settings — a switch is easier to understand beside the thing it turns on.
    ///
    /// It leads on the breathing rate because that is what makes the offer worth
    /// taking: a watch counts the same thing the check-in above asks somebody to
    /// count, every night, without being asked.
    private var invitation: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.close) {
            Text(
                "If you wear an Apple Watch overnight, önd can add weekly sleeping breathing "
                    + "rate, resting heart rate and HRV trends to your coach's context. "
                    + "Nothing is read until you opt in."
            )
            .font(.callout)
            .foregroundStyle(Theme.Ink.secondary)

            Button("Read my watch trends") {
                health.coachReadsHealthTrends = true
                // The ask is its own call: this button is somebody looking at
                // the empty card the grant would fill, which is exactly where a
                // Health sheet belongs.
                health.requestReadAccess()
            }
            .buttonStyle(.bordered)
        }
    }

    private func trends(_ context: CoachHealthContext) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.standard) {
            if let breathing = context.sleepingBreathingRate {
                metric(
                    "Sleeping breathing rate",
                    breathing,
                    unit: HealthUnit(one: "breath a minute", many: "breaths a minute"),
                    note: "Slower than your waking rate for everybody — a separate number "
                        + "from the one you count, not a better version of it."
                )
            }
            if let resting = context.restingHeartRate {
                metric("Resting heart rate", resting, unit: .flat("bpm"))
            }
            if let variability = context.heartRateVariability {
                metric("Heart rate variability", variability, unit: .flat("ms"))
            }

            Text("Weekly averages, read when you open this. Never stored.")
                .font(.caption)
                .foregroundStyle(Theme.Ink.tertiary)
        }
    }

    private func metric(
        _ title: String,
        _ snapshot: HealthSnapshot,
        unit: HealthUnit,
        note: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            Text(sentence(for: snapshot, unit: unit))
                .font(.callout)
                .foregroundStyle(Theme.Ink.secondary)

            if let note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(Theme.Ink.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// The mean, and the trend where there is enough evidence for one. A missing
    /// trend is left unsaid rather than drawn as "no change": too little history
    /// is not the same as a week that matched its baseline, and only one of
    /// those is something the person did.
    private func sentence(for snapshot: HealthSnapshot, unit: HealthUnit) -> String {
        guard let trend = snapshot.trendPhrase(in: unit) else {
            return snapshot.mean(in: unit)
        }
        return "\(snapshot.mean(in: unit)), \(trend)"
    }

    /// Opted in, nothing to show — the state this card was built for.
    ///
    /// It names both causes without choosing between them, because the app
    /// cannot tell: HealthKit does not report a refused read, so "you denied
    /// access" would be a guess, and a wrong one for everybody who simply has no
    /// watch yet. Health is named as the place to check because that is where
    /// the answer actually is.
    private var nothingReadable: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.close) {
            Text("Nothing to read yet.")
                .font(.callout.weight(.semibold))

            Text(
                "This needs a few nights of Apple Watch data and permission to read it. "
                    + "Check Health under Sharing."
            )
            .font(.callout)
            .foregroundStyle(Theme.Ink.secondary)
        }
    }
}

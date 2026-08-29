import OndKit
import OndUI
import SwiftUI

/// What Health has to say about this person's body, marked as read off a
/// watch rather than counted on purpose. The sleeping breathing rate leads
/// and says "sleeping" every time it appears: everybody breathes slower
/// asleep, so read as one series with the counted rate it fakes progress
/// either way. The card exists because the opt-in had no observable effect.
struct HealthTrendsCard: View {
    let health: HealthContextModel

    @Environment(SubscriptionStore.self) private var plus

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.standard) {
            Text("From your watch")
                .eyebrow()

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.standard)
        // Not interactive: the card holds a control rather than being one, so
        // the glass must not flex when the control inside is what was touched.
        .glassCard()
        // Runs on every appearance: a grant made in the Health app between
        // visits changes nothing this screen would otherwise hear about. Not
        // run below the subscription — a Health read behind an offer is a
        // query nobody asked for. Keyed on that answer so a purchase in place
        // runs the read the guard just refused, without leaving the screen.
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

    /// The same invitation, with the price on it. It says what the numbers are
    /// *for* rather than listing them: Apple's Health app shows anybody their
    /// own HRV for nothing — what önd+ sells is the coach reasoning from them.
    private var locked: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.close) {
            Text(
                "If you wear an Apple Watch overnight, önd+ can add weekly sleeping "
                    + "breathing rate, resting heart rate and heart rate variability (HRV) "
                    + "trends to your coach's context, "
                    + "and draw your heart rate around each session on Home."
            )
            .font(.callout)
            .foregroundStyle(Theme.Ink.secondary)

            UpgradePrompt(reason: "Reading your trends is part of", for: .health)
        }
    }

    /// The opt-in, offered where the data would appear rather than only in
    /// Settings. It leads on the breathing rate because that is the pitch: a
    /// watch counts what the check-in above asks for, every night, unasked.
    private var invitation: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.close) {
            Text(
                "If you wear an Apple Watch overnight, önd can add weekly sleeping breathing "
                    + "rate, resting heart rate and heart rate variability (HRV) trends to your "
                    + "coach's context, and draw "
                    + "your heart rate around each session on Home. Nothing is read until you "
                    + "opt in."
            )
            .font(.callout)
            .foregroundStyle(Theme.Ink.secondary)

            Button("Read my heart data") {
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
                    unit: HealthUnit(one: "breath per minute", many: "breaths per minute"),
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

    /// Opted in, nothing to show — the state this card was built for. It names
    /// both causes without choosing: HealthKit does not report a refused read,
    /// so "you denied access" would be a guess, and a wrong one for everybody
    /// who simply has no watch yet.
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

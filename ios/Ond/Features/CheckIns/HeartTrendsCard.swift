import OndKit
import OndUI
import SwiftUI

/// What Health has to say about this person's heart, shown to the person it is
/// about.
///
/// Beside the two measurements they take themselves, and deliberately marked as
/// coming from somewhere else: a pause and a resting rate are counted on
/// purpose, these are read off a watch that was being worn anyway. The heading
/// carries that distinction so the screen never implies somebody sat down and
/// measured their HRV.
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
struct HeartTrendsCard: View {
    let health: HealthContextModel

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
        .background(Theme.Surface.raised, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        // Runs on every appearance rather than once: somebody who granted access
        // in the Health app between visits should find the numbers here, and
        // nothing else would tell this screen that changed.
        .task { await health.loadHeartTrends() }
    }

    @ViewBuilder
    private var content: some View {
        switch health.heartTrends {
        case .off:
            invitation
        case .loading:
            // No spinner: two Health queries against a local daemon are quick,
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

    /// The opt-in, offered where the data would appear rather than only in
    /// Settings — a switch is easier to understand beside the thing it turns on.
    private var invitation: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.close) {
            Text(
                "Your resting heart rate and its variability move with how you sleep, train "
                    + "and recover — and with how you breathe. The coach can read them from "
                    + "Health to answer against your week rather than in general."
            )
            .font(.callout)
            .foregroundStyle(Theme.Ink.secondary)

            Button("Read my heart trends") {
                health.coachReadsHeartTrends = true
            }
            .buttonStyle(.bordered)
        }
    }

    private func trends(_ context: CoachHealthContext) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.standard) {
            if let resting = context.restingHeartRate {
                metric("Resting heart rate", resting, unit: "bpm")
            }
            if let variability = context.heartRateVariability {
                metric("Heart rate variability", variability, unit: "ms")
            }

            Text("Weekly averages, read when you open this. Never stored.")
                .font(.caption)
                .foregroundStyle(Theme.Ink.tertiary)
        }
    }

    private func metric(_ title: String, _ snapshot: HealthSnapshot, unit: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            Text(sentence(for: snapshot, unit: unit))
                .font(.callout)
                .foregroundStyle(Theme.Ink.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// The mean, and the trend where there is enough evidence for one. A missing
    /// trend is left unsaid rather than drawn as "no change": too little history
    /// is not the same as a week that matched its baseline, and only one of
    /// those is something the person did.
    private func sentence(for snapshot: HealthSnapshot, unit: String) -> String {
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
                "This needs a few days of wearing an Apple Watch, and permission to read "
                    + "heart data. Both live in the Health app, under Sharing."
            )
            .font(.callout)
            .foregroundStyle(Theme.Ink.secondary)
        }
    }
}

import OndKit
import OndUI
import SwiftUI

/// The two check-ins, behind one door.
///
/// One door rather than a card each, so a third measurement is a row here
/// instead of another card on whichever tab is hosting them.
///
/// Opened from the Coach tab, because a check-in is the coach's material rather
/// than the journey's: the journey is what you did, a check-in is what your
/// breathing is doing when you are not doing anything about it, and the coach is
/// the only thing in the app that reads either number back — both ride in its
/// briefing and in its rule-based fallback.
///
/// The pair is deliberate. A resting rate measures the habitual pattern a
/// person breathes at; a comfortable pause measures CO2 tolerance. They move
/// independently, which is exactly why two are worth taking and neither is a
/// re-run of the other.
///
/// The rate is first, and that order is a claim rather than a layout. It is the
/// one figure in the app with a validated construct and trials showing that
/// breathing practice moves it — Balban's five-minutes-a-day arm lowered resting
/// respiratory rate over a month — so it is what progress means here. The pause
/// is self-referenced and evidenced far more thinly; it stays because it is a
/// useful thing to know about yourself, not because it is a score. The coach
/// reads them in this same order, and for the same stated reason.
///
/// The watch trends below them are read rather than measured — see
/// `HealthTrendsCard`, which is also the only place the Health opt-in has any
/// visible effect, and where the same rate arrives again as a nightly figure
/// nobody had to sit down for.
struct CheckInsView: View {
    let model: JourneyModel

    /// In the environment rather than passed down, like the rest of what
    /// Settings and this screen share.
    @Environment(HealthContextModel.self) private var health

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.loose) {
                Text("Two short measurements taken at rest. They give your coach context "
                    + "over time — neither is a score to chase.")
                    .font(.callout)
                    .foregroundStyle(Theme.Ink.secondary)

                VStack(spacing: Theme.Spacing.close) {
                    restingRateCard
                    pauseCard
                }

                HealthTrendsCard(health: health)
            }
            .padding(Theme.Spacing.standard)
        }
        .paletteGround()
        .navigationTitle("Check-ins")
        .navigationBarTitleDisplayMode(.inline)
        // The doors carry the numbers, and a pause taken on the wrist or a
        // restore can have changed them since the Coach tab was last drawn.
        .task { await model.refresh() }
    }

    /// The number shown is the *lowest*, which is the good end for this one —
    /// the caption says "slowest" rather than "best" so a number that went down
    /// does not read as a number that got worse.
    private var restingRateCard: some View {
        DoorCard(
            title: "Resting rate",
            caption: model.lowestRestingRate == nil
                ? "Count your breaths for one minute while sitting still."
                : "Slowest recorded. Take it again whenever.",
            value: model.lowestRestingRate.map { "\($0)/min" }
        ) {
            RestingRateTestView(model: model)
        }
        .glassCard(interactive: true)
    }

    private var pauseCard: some View {
        DoorCard(
            title: "Comfortable pause",
            caption: model.personalBest == nil
                ? "A gentle pause, stopped at the first clear urge to breathe."
                : "Longest recorded. Take it again whenever.",
            value: model.personalBest.map { "\($0)s" }
        ) {
            BoltTestView(model: model)
        }
        .glassCard(interactive: true)
    }
}

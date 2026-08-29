import OndKit
import OndUI
import SwiftUI

/// The two check-ins behind one door, opened from the Coach tab — the coach
/// is the only thing in the app that reads either number back. The rate
/// measures the habitual pattern, the pause CO2 tolerance; they move
/// independently. The rate leads as a claim, not a layout: it is the one
/// figure with trial evidence (Balban), and the coach reads the same order.
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
            title: "Resting breathing rate",
            caption: model.lowestRestingRate == nil
                ? "Count your breaths for one minute while sitting still."
                : "Slowest recorded. Take it again whenever.",
            value: model.lowestRestingRate.map { "\($0) breaths per minute" }
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

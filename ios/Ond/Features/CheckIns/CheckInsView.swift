import OndKit
import OndUI
import SwiftUI

struct CheckInsView: View {
    let model: JourneyModel

    /// In the environment rather than passed down, like the rest of what
    /// Settings and this screen share.
    @Environment(HealthContextModel.self) private var health

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.loose) {
                Text("Two short measurements taken at rest. They give your coach context "
                    + "over time.")
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

    private var restingRateCard: some View {
        DoorCard(
            title: "Resting breathing rate",
            caption: model.latestRestingRate == nil
                ? "Count your breaths for one minute while sitting still."
                : "Your latest reading. Take it again when comfortable.",
            value: model.latestRestingRate.map { "\($0) breaths per minute" }
        ) {
            RestingRateTestView(model: model)
        }
        .glassCard(interactive: true)
    }

    private var pauseCard: some View {
        DoorCard(
            title: "Comfortable pause",
            caption: model.latestPause == nil
                ? "A gentle pause, stopped at the first clear urge to breathe."
                : "Your latest reading. Take it again when comfortable.",
            value: model.latestPause.map { "\($0)s" }
        ) {
            BoltTestView(model: model)
        }
        .glassCard(interactive: true)
    }
}

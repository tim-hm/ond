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
/// The pair is deliberate. A comfortable pause measures CO2 tolerance; a resting
/// rate measures the habitual pattern underneath it. They move independently,
/// which is exactly why two are worth taking and neither is a re-run of the
/// other.
struct CheckInsView: View {
    let model: JourneyModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.standard) {
                Text(
                    "Two short measurements of how your breathing is when you're not "
                        + "practising. Neither is a test to win — they are the numbers the "
                        + "coach reads your practice against."
                )
                .font(.callout)
                .foregroundStyle(Theme.Ink.secondary)

                pauseCard
                restingRateCard
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

    private var pauseCard: some View {
        DoorCard(
            title: "Comfortable pause",
            caption: model.personalBest == nil
                ? "A two-minute check-in on your breathing."
                : "Your best so far. Take it again whenever.",
            value: model.personalBest.map { "\($0)s" }
        ) {
            BoltTestView(model: model)
        }
    }

    /// The number shown is the *lowest*, which is the good end for this one —
    /// the caption says "slowest" rather than "best" so a number that went down
    /// does not read as a number that got worse.
    private var restingRateCard: some View {
        DoorCard(
            title: "Resting rate",
            caption: model.lowestRestingRate == nil
                ? "Count your breaths for a minute, sitting still."
                : "Your slowest so far. Take it again whenever.",
            value: model.lowestRestingRate.map { "\($0)/min" }
        ) {
            RestingRateTestView(model: model)
        }
    }
}

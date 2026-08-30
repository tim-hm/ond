import OndKit
import OndUI
import SwiftUI

/// The half of Progress that answers "how am I doing": the four-week chart
/// with its three figures, then where this person stands, then what their
/// heart was doing around it. Everything here is folded from the sessions on
/// this phone except the board, which is the only thing that waits on a
/// network. History is a log rather than a summary, so it never displaces these.
struct PracticeSummary: View {
    let rhythm: PracticeRhythm
    let model: JourneyModel

    /// Supplies the leaderboard and its opt-in flow.
    let profiles: ProfileStore

    @Environment(SubscriptionStore.self) private var plus

    /// The heart around the practice, read from Health for the one card here
    /// that your body answered rather than you.
    @Environment(HealthContextModel.self) private var heart

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.loose) {
            VStack(alignment: .leading, spacing: Theme.Spacing.standard) {
                PracticeChartView(rhythm: rhythm)
                PracticeFigures(rhythm: rhythm)
            }
            .padding(Theme.Spacing.standard)
            .glassCard()

            // Nothing practised is nothing to rank, and a card offering a
            // standing to somebody with no sessions is an advertisement on an
            // empty screen.
            if !model.history.isEmpty {
                BoardCard(model: model, profiles: profiles)
            }

            practiceHeart
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The heart card, only where the tier includes it *and* the heartline is
    /// non-nil. The heartline is nil for every silence there is — not read,
    /// not allowed, no watch, too few readings — so there is no empty state
    /// and no locked teaser: a card about a person's heartbeat is the last
    /// place önd should advertise a subscription.
    @ViewBuilder
    private var practiceHeart: some View {
        if plus.tier >= .healthTrends, let heartline = heart.practiceHeart {
            PracticeHeartCard(heartline: heartline)
        }
    }
}

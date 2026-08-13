import OndKit
import OndStyle
import OndUI
import SwiftUI

/// The goals a list can be narrowed to, as a row of pills.
///
/// One control for two screens — the catalogue and the protocols — because "show
/// me only the sleep ones" is the same question on both, and a second copy would
/// be two rows in one app disagreeing about whether a second tap clears the
/// filter.
///
/// Tapping the active pill clears it, and that is the whole of the clear
/// affordance: an "All" pill at the head of the row would be a sixth control
/// saying what the absence of the other five already says, and it would have to
/// be selected by default — a filter row that opens looking filtered.
///
/// Horizontally scrolling because five pills fit on most phones and none at the
/// largest text sizes. The indicator is hidden: a row of five is not a document,
/// and a bar under it would read as a second, thinner control.
struct GoalFilterRow: View {
    /// Which goals to offer, in the order to offer them. The caller decides,
    /// because "which goals does this list actually hold" is a question about
    /// that list — `TechniqueGoal.present(in:)` for the catalogue,
    /// `ProtocolsBoard.goals` for the protocols.
    let goals: [TechniqueGoal]

    /// The active goal, or nil for the unfiltered list.
    @Binding var selection: TechniqueGoal?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Theme.Spacing.close) {
                ForEach(goals, id: \.self) { goal in
                    FilterPill(
                        title: goal.title,
                        accent: goal.accent,
                        isSelected: selection == goal
                    ) {
                        selection = selection == goal ? nil : goal
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.standard)
            .padding(.vertical, Theme.Spacing.close)
        }
        .scrollIndicators(.hidden)
    }
}

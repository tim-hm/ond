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
/// All is explicit at the head of the row. It gives the absence of a goal a
/// visible control and keeps this native pinned header aligned with the
/// reference composition instead of opening with no selected state.
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
                FilterPill(
                    title: "All",
                    accent: Theme.Accent.brandText,
                    isSelected: selection == nil,
                    showsDot: false
                ) {
                    selection = nil
                }

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
            .padding(.horizontal, Theme.Spacing.standard + Theme.Spacing.tight)
            .padding(.vertical, Theme.Spacing.close)
        }
        .scrollIndicators(.hidden)
        // This row is a pinned section header on both of its screens. Its opaque
        // ground keeps scrolled cards and type from showing through the native
        // navigation chrome while the bar itself remains system-owned.
        .background(Theme.Surface.ground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.Surface.line)
                .frame(height: 1)
        }
    }
}

import OndKit
import OndStyle
import OndUI
import SwiftUI

/// The goals a list can be narrowed to, as a row of pills. One control for
/// the catalogue and the protocols, so two rows cannot disagree about whether
/// a second tap clears the filter. All is explicit at the head, giving the
/// absence of a goal a visible control. Scrolls horizontally — five pills fit
/// on most phones, none at the largest text sizes; the indicator is hidden.
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
            .padding(.horizontal, Theme.Spacing.page)
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
                .frame(height: 0.5)
        }
    }
}

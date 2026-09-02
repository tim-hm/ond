import OndKit
import OndUI
import SwiftUI

/// Every session this device holds, newest first. The Progress tab keeps only
/// the most recent days, so its summary stays on the screen; the whole log is
/// here, a page at a time.
struct SessionHistoryView: View {
    let model: JourneyModel

    /// Resolves the name and the mark each row draws.
    let catalogue: TechniqueListModel
    let own: UserTechniqueModel

    /// The row awaiting confirmation before it and every total it counts
    /// towards are deleted together.
    @State private var toDelete: SessionRecord?

    var body: some View {
        // Whole days rather than the model's row slice: a plate states its
        // day's total, so a day cut at the page boundary would understate it.
        let days = SessionDay.wholeDays(
            of: model.history,
            coveringAtLeast: model.visibleHistory.count
        )
        let legend = SessionLegend(catalogue: catalogue, own: own)
        let hasEarlier = days.sessionCount < model.history.count

        ScrollView {
            // The lazy stack is the scroll view's own child. Wrapped in
            // another stack it is asked for its whole height, which builds
            // every plate of a history that has no ceiling.
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.standard) {
                ForEach(days) { day in
                    SessionDayPlate(day: day, legend: legend) { toDelete = $0 }
                }

                earlierSessions(isOffered: hasEarlier)
            }
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.top, Theme.Spacing.close)
            .padding(.bottom, Theme.Spacing.loose)
        }
        .paletteGround()
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.large)
        .sessionDeletion(of: $toDelete, from: model)
    }

    /// The foot of the log, which is also what asks for the next page. The
    /// lazy stack builds it as the scroll nears the end. It is one view under
    /// all the plates rather than a trigger on every row, so one page cannot
    /// load the next. The button stays for a reader the appearance misses.
    @ViewBuilder
    private func earlierSessions(isOffered: Bool) -> some View {
        if isOffered {
            Button("Show earlier sessions") {
                model.revealEarlierSessions()
            }
            .onAppear { model.revealEarlierSessions() }
            .buttonStyle(.plain)
            .font(.callout)
            // The brand blue that reads as small type: `Breath.inhale`'s own
            // light value measures 4.06:1 on this ground, under the floor.
            .foregroundStyle(Theme.Accent.brandText)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, Theme.Spacing.standard)
        }
    }
}

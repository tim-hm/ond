import OndKit
import OndUI
import SwiftUI

/// One day of practice on its own raised plate: the day and its total, then
/// that day's sessions. The Progress tab and the full history both draw this,
/// so a day reads the same on either.
struct SessionDayPlate: View {
    let day: SessionDay
    let legend: SessionLegend

    /// The row somebody asked to delete. The screen holds the confirmation,
    /// so one dialog covers every plate it draws.
    let delete: (SessionRecord) -> Void

    var body: some View {
        VStack(spacing: 0) {
            SessionDayHeader(day: day)

            ForEach(day.sessions) { record in
                let isFinal = record.id == day.sessions.last?.id

                SessionHistoryRow(
                    record: record,
                    name: legend.names[record.techniqueSlug] ?? record.techniqueSlug.rawValue,
                    goal: legend.goals[record.techniqueSlug]
                )
                .contextMenu {
                    Button("Delete session", systemImage: "trash", role: .destructive) {
                        delete(record)
                    }
                }

                // The hairlines inside a plate separate that day's sessions.
                // What separates one day from the next is the plate's own
                // edge, so the last row draws none.
                if !isFinal {
                    Divider().overlay(Theme.Surface.line)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.standard)
        .padding(.vertical, Theme.Spacing.tight)
        .plate()
    }
}

extension View {
    /// The one question asked before a logged session goes. Written once for
    /// both logs, so the tab and the full history delete on the same terms.
    @MainActor
    func sessionDeletion(
        of record: Binding<SessionRecord?>,
        from model: JourneyModel
    ) -> some View {
        confirmationDialog(
            "Delete this session?",
            isPresented: Binding(
                get: { record.wrappedValue != nil },
                set: {
                    if !$0 {
                        record.wrappedValue = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let chosen = record.wrappedValue else { return }
                record.wrappedValue = nil
                Task { await model.delete(chosen) }
            }
        } message: {
            Text("It comes out of your totals and streak too.")
        }
    }
}

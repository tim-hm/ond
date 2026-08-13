import OndKit
import OndUI
import SwiftUI

/// Every session this person has breathed, newest first.
///
/// A room behind a door on Home rather than half a tab, which is what it was.
/// The numbers Home draws are a fold over this list, so the two are the same
/// information at two resolutions — and the resolution somebody wants most days
/// is the fold. A list that grows for the life of the install does not belong
/// above it.
///
/// Local, so it is complete in airplane mode: the sync runs behind Home, and
/// nothing here waits on it.
///
/// The copy rule holds throughout: celebrate consistency, never pressure.
struct HistoryView: View {
    let model: JourneyModel

    /// For resolving a record's slug to its display name. A session can outlive
    /// the exercise it recorded; the slug then stands in rather than hiding the
    /// row.
    let catalogue: TechniqueListModel

    /// The exercises this person wrote, resolved the same way.
    ///
    /// Beside the catalogue rather than folded into it because they arrive from
    /// a different service — and here at all because without them a living
    /// authored exercise printed its raw slug. The slug is the answer for an
    /// exercise that is *gone*, and "my-box-4-4" beside a session breathed this
    /// morning reads as a bug rather than as a tombstone.
    let own: UserTechniqueModel

    /// The row awaiting the person's confirmation before it goes — deletion
    /// takes the stats with it, so it is asked about, not swiped away.
    @State private var toDelete: SessionRecord?

    var body: some View {
        ScrollView {
            history
                .padding(Theme.Spacing.standard)
        }
        .paletteGround()
        .navigationTitle("Sessions")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var history: some View {
        // Once per redraw rather than once per row: the strip resolves a slug
        // to a name for every row it draws, and a linear scan each time turned
        // a bounded list back into work proportional to the catalogue times it.
        let names = techniqueNames

        return VStack(alignment: .leading, spacing: Theme.Spacing.standard) {
            if model.history.isEmpty {
                Text("Every session you breathe lands here.")
                    .font(.callout)
                    .foregroundStyle(Theme.Ink.secondary)
            } else {
                // Lazy over a bounded slice, because this grows for the life of
                // the install: an eager stack builds every row to show the four
                // on screen, and a lazy one over the whole history still holds
                // every row it has ever built. A page at a time keeps both the
                // diff and the live view count flat.
                LazyVStack(spacing: 0) {
                    ForEach(model.visibleHistory) { record in
                        SessionHistoryRow(
                            record: record,
                            name: names[record.techniqueSlug] ?? record.techniqueSlug
                        )
                        // A context menu rather than a swipe: these rows
                        // live in a ScrollView, where swipe actions do not
                        // exist, and a visible affordance per row would
                        // put a delete button beside every breath taken.
                        .contextMenu {
                            Button("Delete session", systemImage: "trash", role: .destructive) {
                                toDelete = record
                            }
                        }
                        Divider().overlay(Theme.Surface.line)
                    }
                }

                if model.hasEarlierSessions {
                    Button("Show earlier sessions") {
                        model.revealEarlierSessions()
                    }
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, Theme.Spacing.tight)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .confirmationDialog(
            "Delete this session?",
            isPresented: Binding(
                get: { toDelete != nil },
                set: {
                    if !$0 {
                        toDelete = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let record = toDelete else { return }
                toDelete = nil
                Task { await model.delete(record) }
            }
        } message: {
            Text("It comes out of your totals and streak too.")
        }
    }

    /// Display names by slug. A session can outlive the exercise it recorded,
    /// and a slug with no entry here stands in for its name rather than hiding
    /// the row.
    private var techniqueNames: [String: String] {
        let catalogued = if case let .loaded(techniques) = catalogue.state {
            techniques
        } else {
            [Technique]()
        }

        return Dictionary(
            (catalogued + own.techniques).map { ($0.slug, $0.name) }
        ) { _, latest in latest }
    }
}

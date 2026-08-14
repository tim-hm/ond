import OndKit
import OndUI
import SwiftUI

/// The shape and the record of this person's practice.
///
/// Home carries the compact fold and opens this room for the detailed one: the
/// last four weeks when there is enough rhythm to draw, followed by every
/// session newest first. The list grows for the life of the install, which is
/// why Home keeps only the summary rather than either of these resolutions.
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
        let rhythm = practiceRhythm

        return VStack(alignment: .leading, spacing: Theme.Spacing.standard) {
            if rhythm.isWorthCharting {
                PracticeChartView(rhythm: rhythm)
            }

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

    /// Everything that can name or categorise a session still present on this
    /// device. Authored exercises arrive independently of the catalogue, so the
    /// chart and the rows both have to observe the union rather than whichever
    /// source loaded first.
    private var techniques: [Technique] {
        let catalogued = if case let .loaded(techniques) = catalogue.state {
            techniques
        } else {
            [Technique]()
        }

        return catalogued + own.techniques
    }

    /// Display names by slug. A session can outlive the exercise it recorded,
    /// and a slug with no entry here stands in rather than hiding the row.
    private var techniqueNames: [String: String] {
        Dictionary(
            techniques.map { ($0.slug, $0.name) }
        ) { _, latest in latest }
    }

    /// The four-week detail Home deliberately leaves behind this door.
    /// Unknown historical slugs have no goal to claim and are omitted on
    /// `PracticeRhythm`'s own rule, while their rows remain visible below.
    private var practiceRhythm: PracticeRhythm {
        let goals = techniques.reduce(into: [String: TechniqueGoal]()) { result, technique in
            result[technique.slug] = technique.goal
        }
        return PracticeRhythm(sessions: model.history, goals: goals)
    }
}

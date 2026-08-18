import OndKit
import OndUI
import SwiftUI

/// Progress: the shape, record and shared context of this person's practice.
///
/// The four-week shape leads, then the three totals it is the picture of, then
/// the one card that reaches past this device, then the sessions themselves. In
/// that order because it runs from the most folded to the least: a rhythm, a
/// number, a standing, a record.
///
/// Everything above the board is computed here from the sessions on this phone,
/// so the tab is complete in airplane mode. `BoardCard` is the only thing on it
/// that can be waiting on a network, and it is built to say nothing while it is.
struct PracticeProgressView: View {
    let model: JourneyModel

    /// Resolves historical slugs and supplies the goals the chart folds by.
    let catalogue: TechniqueListModel

    /// Authored exercises arrive from their own service but count in the same
    /// chart and name their sessions by the same rule as curated exercises.
    let own: UserTechniqueModel

    /// Supplies the leaderboard and its opt-in flow.
    let profiles: ProfileStore

    /// The row awaiting confirmation before it and its contribution to every
    /// figure above are deleted together.
    @State private var toDelete: SessionRecord?

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .padding(Theme.Spacing.standard)
            }
            .paletteGround()
            .navigationTitle("Progress")
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
        // The local fold draws first; the catalogue and sync then finish behind
        // content already on screen. This tab must be complete even when Home
        // has never loaded either shared model for it.
        .task {
            async let catalogueLoaded: Void = catalogue.loadIfNeeded()
            await model.refresh()
            await catalogueLoaded
            await model.sync()
        }
        .task { await own.loadIfNeeded() }
    }

    private var content: some View {
        let names = techniqueNames
        let goals = techniqueGoals

        return VStack(alignment: .leading, spacing: Theme.Spacing.loose) {
            PracticeChartView(rhythm: PracticeRhythm(sessions: model.history, goals: goals))
            PracticeFigures(stats: model.stats)
            BoardCard(model: model, profiles: profiles)

            LabelledSection(title: "Sessions") {
                sessionHistory(names: names, goals: goals)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func sessionHistory(
        names: [String: String],
        goals: [String: TechniqueGoal]
    ) -> some View {
        if model.history.isEmpty {
            Text("Every session you breathe lands here.")
                .font(.callout)
                .foregroundStyle(Theme.Ink.secondary)
        } else {
            // The bounded slice gives Dynamic Type a stable hierarchy to
            // reflow. Revealing another page changes only this local view; the
            // complete history already feeds the summary and chart.
            VStack(spacing: 0) {
                ForEach(model.visibleHistory) { record in
                    SessionHistoryRow(
                        record: record,
                        name: names[record.techniqueSlug] ?? record.techniqueSlug,
                        goal: goals[record.techniqueSlug]
                    )
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

    /// Everything that can name or categorise a session still on this device.
    private var techniques: [Technique] {
        let catalogued = if case let .loaded(techniques) = catalogue.state {
            techniques
        } else {
            [Technique]()
        }

        return catalogued + own.techniques
    }

    /// A missing exercise leaves its historical slug visible instead of hiding
    /// the session that outlived it.
    private var techniqueNames: [String: String] {
        Dictionary(
            techniques.map { ($0.slug, $0.name) }
        ) { _, latest in latest }
    }

    /// What each session was for, keyed by slug.
    ///
    /// Read by the chart, which drops the sessions it cannot place — a session
    /// filed under a goal it was never breathed for would make the caption's
    /// "mostly relax" wrong — and by the history rows, which keep the row and
    /// draw a neutral dot instead. Two different right answers to one missing
    /// slug, from one join.
    private var techniqueGoals: [String: TechniqueGoal] {
        techniques.reduce(into: [String: TechniqueGoal]()) { result, technique in
            result[technique.slug] = technique.goal
        }
    }
}

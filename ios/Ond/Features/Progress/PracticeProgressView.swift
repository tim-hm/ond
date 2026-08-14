import OndKit
import OndUI
import SwiftUI

/// Progress: the shape, record and shared context of this person's practice.
///
/// The chart and sessions come from this device. Leaderboards lead as the one
/// door that reaches beyond it; the four-week rhythm then bridges that shared
/// context into the growing local history below.
struct PracticeProgressView: View {
    let model: JourneyModel

    /// Resolves historical slugs and supplies the goals the chart folds by.
    let catalogue: TechniqueListModel

    /// Authored exercises arrive from their own service but count in the same
    /// chart and name their sessions by the same rule as curated exercises.
    let own: UserTechniqueModel

    /// Names the leaderboard door and supplies the opt-in screen behind it.
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
        let rhythm = practiceRhythm

        return VStack(alignment: .leading, spacing: Theme.Spacing.loose) {
            leaderboardDoor
            PracticeChartView(rhythm: rhythm)

            LabelledSection(title: "Sessions") {
                sessionHistory(names: names)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The leaderboard keeps its existing gate and connection handling behind
    /// one stable door rather than making remote state part of this local fold.
    private var leaderboardDoor: some View {
        DoorCard(
            title: "Leaderboards",
            caption: profiles.profile.displayName.isEmpty
                ? "Optional, and off until you pick a name."
                : "You're listed as \(profiles.profile.displayName)."
        ) {
            LeaderboardView(model: model, profiles: profiles)
        }
        .accessibilityIdentifier("leaderboards-door")
    }

    @ViewBuilder
    private func sessionHistory(names: [String: String]) -> some View {
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
                        name: names[record.techniqueSlug] ?? record.techniqueSlug
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

    /// The four-week detail, omitting unknown slugs that no longer have a goal
    /// while retaining their rows in the history below.
    private var practiceRhythm: PracticeRhythm {
        let goals = techniques.reduce(into: [String: TechniqueGoal]()) { result, technique in
            result[technique.slug] = technique.goal
        }
        return PracticeRhythm(sessions: model.history, goals: goals)
    }
}

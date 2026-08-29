import OndKit
import OndUI
import SwiftUI

/// Progress: the shape, record and shared context of this person's practice.
///
/// The four-week shape leads, then the three totals it is the picture of, then
/// — for a subscriber with a watch — the heart around those sessions, then the
/// sessions themselves, then the one card that reaches past this device. From
/// the most folded to the least: a rhythm, a number, a reading, a record, a
/// standing.
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

    @Environment(SubscriptionStore.self) private var plus

    /// The heart around the practice, read from Health for the one card here
    /// that your body answered rather than you. In the environment because it
    /// is the install's, shared with the coach and the check-ins screen.
    @Environment(HealthContextModel.self) private var heart

    /// The row awaiting confirmation before it and its contribution to every
    /// figure above are deleted together.
    @State private var toDelete: SessionRecord?

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .padding(.horizontal, Theme.Spacing.page)
                    .padding(.top, Theme.Spacing.close)
                    .padding(.bottom, Theme.Spacing.loose)
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
        // The heart card's read. Keyed on all three things that change what it
        // should draw: the tier, the opt-in — granted in Settings, and nothing
        // else would re-run the read — and the sessions themselves, by id, so a
        // deletion or a restore moves the key even when the newest session has
        // not changed. The model's own freshness window is what keeps a tab hop
        // from re-reading.
        .task(id: HeartRead(
            tier: plus.tier,
            readsHealth: heart.coachReadsHealthTrends,
            sessions: model.history.map(\.id)
        )) {
            await heart.loadPracticeHeart(from: model.history)
        }
    }

    private var content: some View {
        let names = techniqueNames
        let goals = techniqueGoals
        let rhythm = PracticeRhythm(sessions: model.history, goals: goals)

        return VStack(alignment: .leading, spacing: Theme.Spacing.loose) {
            VStack(alignment: .leading, spacing: Theme.Spacing.standard) {
                PracticeChartView(rhythm: rhythm)
                PracticeFigures(rhythm: rhythm)
            }
            .padding(Theme.Spacing.standard)
            .glassCard()

            practiceHeart

            LabelledSection(title: "History") {
                sessionHistory(names: names, goals: goals)
            }

            BoardCard(model: model, profiles: profiles)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The heart card, only where there is something true to draw: the tier
    /// includes it *and* the heartline is non-nil. Both, deliberately — the
    /// heartline is nil for every silence there is (not read, not allowed, no
    /// watch on a wrist, too few readings to mean anything), so there is no
    /// empty state and no locked teaser. A card about a person's heartbeat is
    /// the last place önd should advertise a subscription.
    @ViewBuilder
    private var practiceHeart: some View {
        if plus.tier >= .healthTrends, let heartline = heart.practiceHeart {
            PracticeHeartCard(heartline: heartline)
        }
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Spacing.standard)
                .glassCard()
        } else {
            // The bounded slice gives Dynamic Type a stable hierarchy to
            // reflow. Revealing another page changes only this local view; the
            // complete history already feeds the summary and chart.
            VStack(spacing: 0) {
                ForEach(
                    Array(model.visibleHistory.enumerated()),
                    id: \.element.id
                ) { index, record in
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

                    if index < model.visibleHistory.count - 1 {
                        Divider().overlay(Theme.Surface.line)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.standard)
            .glassCard()

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

    /// What each resolvable session was for, keyed by slug.
    ///
    /// The chart keeps sessions it cannot place in its totals but excludes them
    /// from the optional "mostly relax" caption; a guessed goal would make that
    /// sentence wrong. History keeps the same row and draws a neutral dot.
    private var techniqueGoals: [String: TechniqueGoal] {
        techniques.reduce(into: [String: TechniqueGoal]()) { result, technique in
            result[technique.slug] = technique.goal
        }
    }
}

/// What has to change before the heart around your practice is read again.
///
/// A named value rather than a tuple, because `task(id:)` wants one `Equatable`
/// value and a tuple is not one. The sessions arrive as ids rather than as the
/// records: the whole history compares every field of every session on each
/// pass, and what this asks is only whether the set of practices moved.
private struct HeartRead: Equatable {
    let tier: SubscriptionTier
    let readsHealth: Bool
    let sessions: [UUID]
}

import OndKit
import OndUI
import SwiftUI

/// Progress: the shape, record and shared context of this person's practice.
/// The summary sits first and whole — chart, figures, board — because it is
/// what "how am I doing" is asked of; the log follows it under a rule and
/// never pushes it off the screen. Everything above the board is computed from
/// the sessions on this phone, so the tab is complete in airplane mode.
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

    /// The row awaiting confirmation before it and every total it counts
    /// towards are deleted together.
    @State private var toDelete: SessionRecord?

    /// Whether the whole log is open. A flag plus `navigationDestination`
    /// rather than a link inside the door: deleting the last earlier session
    /// closes the door, and a link taken away under its own screen pops it.
    @State private var isShowingHistory = false

    /// What the summary and the log are set apart by. The refresh spec's own
    /// number rather than a step off the spacing scale, as the page margin is.
    private static let historyGap: CGFloat = 30

    /// How much practice the tab's log shows: the most recent whole days that
    /// hold this many sessions between them. A number rather than a page,
    /// because the log here is the last thing you did and not the record —
    /// the record is one door away, and the summary must stay above the fold.
    private static let recentSessions = 5

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .padding(.top, Theme.Spacing.close)
                    .padding(.bottom, Theme.Spacing.loose)
            }
            .paletteGround()
            .navigationTitle("Progress")
            .navigationDestination(isPresented: $isShowingHistory) {
                SessionHistoryView(model: model, catalogue: catalogue, own: own)
            }
            .sessionDeletion(of: $toDelete, from: model)
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
        // The heart card's read, keyed on all three things that change what
        // it should draw: the tier, the opt-in — granted in Settings, which
        // nothing else here would notice — and the shape of the history, so a
        // deletion or a restore moves the key. The model's own freshness
        // window is what keeps a tab hop from re-reading.
        .task(id: HeartRead(
            tier: plus.tier,
            readsHealth: heart.coachReadsHealthTrends,
            sessionCount: model.history.count,
            newestSession: model.history.first?.id
        )) {
            await heart.loadPracticeHeart(from: model.history)
        }
    }

    private var content: some View {
        let legend = SessionLegend(catalogue: catalogue, own: own)
        let rhythm = PracticeRhythm(sessions: model.history, goals: legend.goals)
        // Whole days rather than a count of rows: a plate states its day's
        // total, so a day cut short would understate it.
        let days = SessionDay.wholeDays(
            of: model.history,
            coveringAtLeast: Self.recentSessions
        )

        return LazyVStack(alignment: .leading, spacing: 0) {
            ScreenSubtitle("What you have practised, not how well.")

            PracticeSummary(rhythm: rhythm, model: model, profiles: profiles)
                .padding(.horizontal, Theme.Spacing.page)

            if !days.isEmpty {
                history(days, legend: legend)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The log: the rule and the gap that set it apart from the summary, the
    /// heading with the lifetime count, the recent days, and the door to the
    /// rest where these days are not all of it.
    private func history(_ days: [SessionDay], legend: SessionLegend) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
                .overlay(Theme.Surface.line)
                .padding(.top, Theme.Spacing.loose)

            LabelledSection(title: "History · \(lifetime)") {
                VStack(alignment: .leading, spacing: Theme.Spacing.standard) {
                    ForEach(days) { day in
                        SessionDayPlate(day: day, legend: legend) { toDelete = $0 }
                    }
                }
            }
            .padding(.top, Self.historyGap)

            if days.sessionCount < model.history.count {
                DoorCard(title: "All history", caption: lifetime, action: {
                    isShowingHistory = true
                })
                .glassCard(interactive: true)
                .accessibilityIdentifier("all-history-door")
                .padding(.top, Theme.Spacing.standard)
            }
        }
        .padding(.horizontal, Theme.Spacing.page)
    }

    /// The lifetime count, worded for the heading and the door by the rule the
    /// summary figures already use. Zero never reaches it: nothing here draws
    /// until a session is on the device.
    private var lifetime: String {
        SessionSummaryLines.counted(model.stats.sessions, of: "session")
            .map { "\($0.value) \($0.label)" } ?? "no sessions"
    }
}

/// What has to change before the heart around your practice is read again. A
/// named value because `task(id:)` wants one `Equatable` value and a tuple is
/// not one. The question is only whether the set of practices moved, which the
/// count and the newest id answer: an array of every session's id would be
/// built and compared on every draw of the tab.
private struct HeartRead: Equatable {
    let tier: SubscriptionTier
    let readsHealth: Bool
    let sessionCount: Int
    let newestSession: UUID?
}

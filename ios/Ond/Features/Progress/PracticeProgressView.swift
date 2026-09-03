import OndKit
import OndUI
import SwiftUI

/// Progress: the shape, record and shared context of this person's practice.
/// The summary sits first and whole — chart, figures, board — because it is
/// what "how am I doing" is asked of; the log follows under its own heading
/// and never pushes it off the screen. Everything above the board is computed from
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

    /// The log: a heading carrying the lifetime count and the way to the whole
    /// record, then the recent days. The gap above is the only thing setting
    /// the log apart from the summary — a section heading is a break already,
    /// and a rule over it draws a second one.
    private func history(_ days: [SessionDay], legend: SessionLegend) -> some View {
        LabelledSection(title: "History · \(lifetime)") {
            if days.sessionCount < model.history.count {
                seeAll
            }
        } content: {
            VStack(alignment: .leading, spacing: Theme.Spacing.standard) {
                ForEach(days) { day in
                    SessionDayPlate(day: day, legend: legend) { toDelete = $0 }
                }
            }
        }
        .padding(.top, Theme.Spacing.section)
        .padding(.horizontal, Theme.Spacing.page)
    }

    /// The way to the whole record, on the heading rather than under the last
    /// plate: it opens the log, not the day it would have sat beneath.
    /// Offered only where the tab is not already showing everything.
    private var seeAll: some View {
        Button("See all") { isShowingHistory = true }
            .font(.footnote.weight(.medium))
            .tracking(1.3)
            .textCase(.uppercase)
            // The brand blue that reads as small type, as the log's own
            // paging button uses: `Breath.inhale` measures 4.06:1 here.
            .foregroundStyle(Theme.Accent.brandText)
            .tapTarget()
            .accessibilityIdentifier("all-history-door")
            .accessibilityLabel("See all history")
            .accessibilityHint("Opens every session this device holds")
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

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

    /// The row awaiting confirmation before it and its contribution to every
    /// figure above are deleted together.
    @State private var toDelete: SessionRecord?

    /// What the summary and the log are set apart by. The refresh spec's own
    /// number rather than a step off the spacing scale, as the page margin is.
    private static let historyGap: CGFloat = 30

    var body: some View {
        NavigationStack {
            ScrollView {
                content
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
        // The heart card's read, keyed on all three things that change what
        // it should draw: the tier, the opt-in — granted in Settings, which
        // nothing else here would notice — and the session ids, so a deletion
        // or a restore moves the key. The model's own freshness window is
        // what keeps a tab hop from re-reading.
        .task(id: HeartRead(
            tier: plus.tier,
            readsHealth: heart.coachReadsHealthTrends,
            sessions: model.history.map(\.id)
        )) {
            await heart.loadPracticeHeart(from: model.history)
        }
    }

    /// One lazy stack rather than nested ones, because the day headers stick to
    /// the top of the scroll on the way past and only a section directly inside
    /// the stack can be pinned.
    private var content: some View {
        let names = techniqueNames
        let goals = techniqueGoals
        let rhythm = PracticeRhythm(sessions: model.history, goals: goals)
        // Whole days rather than the model's row slice: a header states its
        // day's total, so a day cut at the page boundary would understate it.
        let days = SessionDay.wholeDays(
            of: model.history,
            coveringAtLeast: model.visibleHistory.count
        )
        let hasEarlier = days.reduce(0) { $0 + $1.sessions.count } < model.history.count

        return LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
            PracticeSummary(rhythm: rhythm, model: model, profiles: profiles)
                .padding(.horizontal, Theme.Spacing.page)

            if !days.isEmpty {
                historyHeading

                ForEach(days) { day in
                    Section {
                        rows(
                            of: day,
                            names: names,
                            goals: goals,
                            pagesOn: hasEarlier && day.id == days.last?.id
                        )
                    } header: {
                        SessionDayHeader(day: day)
                    }
                }

                earlierSessions(isOffered: hasEarlier)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The rule and the gap that set the log apart from the summary, and the
    /// log's own heading. The heading carries the lifetime count so the list's
    /// depth is legible without scrolling it.
    private var historyHeading: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
                .overlay(Theme.Surface.line)
                .padding(.top, Theme.Spacing.loose)

            // A heading with nothing under it: its rows are pinned sections,
            // which only stick when they sit directly in the lazy stack.
            LabelledSection(title: historyTitle) { EmptyView() }
                .padding(.top, Self.historyGap)
        }
        .padding(.horizontal, Theme.Spacing.page)
        .padding(.bottom, Theme.Spacing.close)
    }

    private var historyTitle: String {
        let lifetime = model.stats.sessions
        return lifetime == 1 ? "History · 1 session" : "History · \(lifetime) sessions"
    }

    /// One day's rows. Where `pagesOn` is set, reaching the last row asks for
    /// the next page — the trigger travels with the data, so a page cannot
    /// load a page, and it is absent when there is nothing left to load.
    private func rows(
        of day: SessionDay,
        names: [TechniqueSlug: String],
        goals: [TechniqueSlug: TechniqueGoal],
        pagesOn: Bool
    ) -> some View {
        VStack(spacing: 0) {
            ForEach(day.sessions) { record in
                let isFinal = record.id == day.sessions.last?.id

                SessionHistoryRow(
                    record: record,
                    name: names[record.techniqueSlug] ?? record.techniqueSlug.rawValue,
                    goal: goals[record.techniqueSlug]
                )
                .contextMenu {
                    Button("Delete session", systemImage: "trash", role: .destructive) {
                        toDelete = record
                    }
                }
                .onAppear {
                    if pagesOn, isFinal {
                        model.revealEarlierSessions()
                    }
                }

                if !isFinal {
                    Divider().overlay(Theme.Surface.line)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.page)
    }

    /// The explicit way to the next page, for somebody who reaches the end by
    /// a means the last row's appearance does not cover.
    @ViewBuilder
    private func earlierSessions(isOffered: Bool) -> some View {
        if isOffered {
            Button("Show earlier sessions") {
                model.revealEarlierSessions()
            }
            .buttonStyle(.plain)
            .font(.callout)
            // The brand blue that reads as small type: `Breath.inhale`'s own
            // light value measures 4.01:1 on this ground, under the floor.
            .foregroundStyle(Theme.Accent.brandText)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, Theme.Spacing.standard)
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
    private var techniqueNames: [TechniqueSlug: String] {
        Dictionary(
            techniques.map { ($0.slug, $0.name) }
        ) { _, latest in latest }
    }

    /// What each resolvable session was for, keyed by slug.
    ///
    /// The chart keeps sessions it cannot place in its totals but excludes them
    /// from the optional "mostly relax" caption; a guessed goal would make that
    /// sentence wrong. History keeps the same row and draws a neutral dot.
    private var techniqueGoals: [TechniqueSlug: TechniqueGoal] {
        techniques.reduce(into: [TechniqueSlug: TechniqueGoal]()) { result, technique in
            result[technique.slug] = technique.goal
        }
    }
}

/// What has to change before the heart around your practice is read again. A
/// named value because `task(id:)` wants one `Equatable` value and a tuple is
/// not one. Session ids rather than records: the question is only whether the
/// set of practices moved, not whether any field of one did.
private struct HeartRead: Equatable {
    let tier: SubscriptionTier
    let readsHealth: Bool
    let sessions: [UUID]
}

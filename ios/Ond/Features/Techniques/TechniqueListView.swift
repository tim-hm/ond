import OndKit
import OndStyle
import OndUI
import SwiftUI

/// The whole catalogue, grouped by what each exercise is for.
///
/// Its own root rather than part of Home: someone who wants to breathe takes
/// what Home or the Protocols list is already offering them, and someone who
/// wants to read about twelve exercises has come here deliberately. The model
/// arrives shared with both — three views onto one load.
struct TechniqueListView: View {
    let model: TechniqueListModel
    let own: UserTechniqueModel
    let sessions: any SessionRecording
    let assistant: any AssistantReading

    /// Only ever read on the pushed detail screen, whose coach door opens a
    /// conversation. Threaded rather than reached for from the environment on the
    /// same terms as everything else here: this root's dependencies are the
    /// composition root's to state.
    let chats: any ConversationStoring

    @Environment(SubscriptionStore.self) private var plus
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Whether somebody tapped a locked exercise. Which one is not kept: there
    /// is one subscription, and the paywall says the same thing whichever row
    /// was tapped.
    @State private var isShowingPaywall = false

    /// Whether the composer is open on a new exercise. Editing an existing one
    /// happens from its detail screen, where the thing being edited is already
    /// on screen.
    @State private var isComposing = false

    /// Which goal the list is narrowed to, or nil for the whole catalogue.
    ///
    /// Not persisted. A filter is a thing somebody is doing right now, and a
    /// list that opened three days later still holding two of its eleven
    /// exercises would read as a catalogue that had shrunk.
    @State private var goal: TechniqueGoal?

    var body: some View {
        NavigationStack {
            content
                .safeAreaInset(edge: .top, spacing: 0) { filters }
                .paletteGround()
                .navigationTitle("Exercises")
                .toolbar { composeButton }
                .navigationDestination(for: Technique.self) { technique in
                    TechniqueDetailView(
                        technique: technique,
                        own: own,
                        sessions: sessions,
                        assistant: assistant,
                        chats: chats,
                        catalogue: model
                    )
                }
                .paywall(for: .general, isPresented: $isShowingPaywall)
                .sheet(isPresented: $isComposing) {
                    if let limits = own.limits {
                        TechniqueComposerView(model: own, limits: limits)
                    }
                }
        }
        // Home usually starts the shared load first, but this tab must not
        // depend on ever having visited it.
        .task { await model.loadIfNeeded() }
        // Separate from the catalogue's load rather than sequenced after it: the
        // two are different services, and somebody's own exercises should not
        // wait on nine curated ones.
        .task { await own.loadIfNeeded() }
    }

    /// New, or nothing.
    ///
    /// Absent rather than disabled until the limits arrive and while the ceiling
    /// is reached: a `+` that does nothing when tapped is worse than no `+`, and
    /// the ceiling is explained on the exercise somebody would have to delete
    /// rather than on the button that will not open.
    @ToolbarContentBuilder
    private var composeButton: some ToolbarContent {
        if own.hasRoomForAnother {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isComposing = true
                } label: {
                    Label("New exercise", systemImage: "plus")
                }
            }
        }
    }

    /// The pill row, pinned under the title rather than scrolled with the list.
    ///
    /// A filter that scrolls away is one somebody has to go back up to turn off,
    /// and the list under an active pill is short by definition — the row would
    /// be off screen exactly when it is most needed.
    ///
    /// Silent unless the catalogue has landed: pills over a spinner are a
    /// control that narrows nothing, and pills over a failure are a control
    /// offered instead of the retry button beside it.
    @ViewBuilder
    private var filters: some View {
        if case let .loaded(techniques) = model.state, !techniques.isEmpty {
            GoalFilterRow(goals: TechniqueGoal.present(in: techniques), selection: $goal)
        }
    }

    /// The exercises this person wrote, above the catalogue — somebody who has
    /// written their own came back for it.
    ///
    /// Silent while loading and while there are none: an empty section
    /// explaining a feature is an advertisement, and the New button is already
    /// the invitation. A *failure* is not silent, though. Somebody whose
    /// exercises did not load would otherwise see a screen that looks exactly
    /// like one where they never wrote any.
    ///
    /// That failure is now the first-run-offline case alone. The repository
    /// beneath caches, and the model keeps a drawn list standing through a
    /// refresh that fails, so reaching here means this identity has never once
    /// had an answer from the server.
    @ViewBuilder
    private var ownSection: some View {
        switch own.state {
        case .loading:
            EmptyView()

        case let .loaded(list) where !matching(list.techniques).isEmpty:
            Section {
                ForEach(matching(list.techniques)) { technique in
                    NavigationLink(value: technique) {
                        TechniqueRow(technique: technique)
                    }
                    .listRowBackground(Color.clear)
                }

                newExerciseRow
            } header: {
                ownHeader
            }

        case .loaded:
            EmptyView()

        case let .failed(message):
            Section {
                InlineRetry(message: message) {
                    Task { await own.load() }
                }
            } header: {
                ownHeader
            }
            .listRowBackground(Color.clear)
        }
    }

    private var ownHeader: some View {
        Text("Yours")
            .font(.title3.weight(.semibold))
            .foregroundStyle(Theme.Ink.primary)
            .textCase(nil)
    }

    /// The way to write one, at the foot of the ones already written — where
    /// somebody who has just read their own three is standing.
    ///
    /// A second door to the toolbar's `+`, and deliberately: the toolbar button
    /// is a glyph in chrome that says nothing about what it makes, and it is at
    /// the far end of the screen from the section it adds to. Absent on the same
    /// terms as that button — a row that opens nothing when the ceiling is
    /// reached would be worse than no row.
    @ViewBuilder
    private var newExerciseRow: some View {
        if own.hasRoomForAnother {
            Button {
                isComposing = true
            } label: {
                Label("New exercise", systemImage: "plus")
                    .font(.body)
                    .foregroundStyle(Theme.Accent.brandText)
                    .padding(.vertical, Theme.Spacing.close)
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .accessibilityIdentifier("new-exercise-row")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView()

        // Same guard as home: an empty catalogue is an answer worth naming,
        // not a blank list.
        case let .loaded(techniques) where techniques.isEmpty:
            EmptyCatalogueView {
                Task { await model.refresh() }
            }

        case let .loaded(techniques):
            List {
                // Leads the catalogue rather than replacing it: somebody who
                // came here to browse still browses, and somebody who wants to
                // be told what to do is told first.
                //
                // Out entirely under an active pill, though. A strip suggesting
                // one exercise above a list somebody has just narrowed by hand
                // is the app answering a question that was not asked, and the
                // suggestion does not read the filter — so half the time it
                // would suggest something the filter has hidden.
                if goal == nil {
                    SuggestedForYouView(techniques: techniques, assistant: assistant)
                }

                ownSection

                catalogueSection(of: matching(techniques))
            }
            .listStyle(.plain)

        case let .failed(message):
            ReferenceRetryView(
                title: "Can't reach the catalogue",
                message: message
            ) {
                Task { await model.refresh() }
            }
        }
    }

    /// Every curated exercise, ordered by what it is for and headed by nothing at
    /// all.
    ///
    /// The five goal headers this replaced pinned themselves under the title in a
    /// `.plain` list and swapped as you scrolled — a line of moving type over a
    /// screen somebody is reading. What each one said is now the first word of
    /// its rows' own caption, where it travels with the exercise it describes
    /// instead of hovering above it.
    ///
    /// Nothing replaced them, not even one standing header: an unheaded section
    /// pins nothing, so scrolling the catalogue moves type rather than parking it,
    /// and the two sections that *can* stand above this one both announce
    /// themselves — Yours by name, the suggestion strip by the caption in its
    /// footer. A header here would have to say "All exercises" under a title
    /// already reading Exercises to earn its line, and it does not.
    ///
    /// No rules either, not even at the goal changes. A line drawn where the
    /// grouping shifts is a claim that something changed, and with nothing left
    /// naming the groups it is a claim nobody can read — the rule either earns a
    /// heading to explain it or it goes, and a heading is what came out. The order
    /// still groups like with like, and each row says what it is for in its own
    /// caption; the bold name is what marks where one exercise begins.
    private func catalogueSection(of techniques: [Technique]) -> some View {
        Section {
            ForEach(Self.ordered(techniques)) { technique in
                row(for: technique)
                    .listRowSeparator(.hidden)
            }
        } footer: {
            rhythmCaption
        }
    }

    /// What the bars on the right of each row are, said once at the foot of the
    /// list rather than per row.
    ///
    /// Silent at accessibility sizes, where the rows draw no bars: a caption
    /// explaining a figure nobody can see is a line of type spent on nothing.
    @ViewBuilder
    private var rhythmCaption: some View {
        if !dynamicTypeSize.isAccessibilitySize {
            Text("Rhythm bars are the stages, to scale. Holds are indigo wherever they appear.")
                .font(.caption)
                .foregroundStyle(Theme.Ink.tertiary)
                .padding(.top, Theme.Spacing.close)
        }
    }

    /// `techniques` narrowed to the active goal, or all of them.
    ///
    /// One rule for both sections, so a pill cannot thin the catalogue while
    /// leaving Yours intact — the exercises somebody wrote carry a goal like
    /// every other, and a filter that skipped them would be a filter that half
    /// worked.
    private func matching(_ techniques: [Technique]) -> [Technique] {
        guard let goal else { return techniques }
        return techniques.filter { $0.goal == goal }
    }

    /// The catalogue in goal order.
    ///
    /// Flattened rather than nested `ForEach`es, so the run is one list of rows
    /// with one separator rule applied to all of it — the shape that made the
    /// per-goal rules easy to take out again.
    private static func ordered(_ techniques: [Technique]) -> [Technique] {
        TechniqueGoal.present(in: techniques).flatMap { goal in
            techniques.filter { $0.goal == goal }
        }
    }

    /// A locked exercise is a row like any other that opens the paywall
    /// instead of the detail screen.
    ///
    /// Listed rather than hidden, and drawn at full strength rather than dimmed:
    /// if a future exercise costs önd+, somebody still has to be able to read
    /// what they would be getting. Dimming reads as a punishment for not having
    /// paid; a lock beside a name and a summary reads as an invitation, which is
    /// what this is. The shipped catalogue currently reaches only the unlocked
    /// branch.
    ///
    /// A locked exercise never reaches `SessionLaunchResolver`, but that gate is
    /// the one that actually holds — this only decides which sheet opens.
    @ViewBuilder
    private func row(for technique: Technique) -> some View {
        if technique.isUnlocked(for: plus.tier) {
            NavigationLink(value: technique) {
                TechniqueRow(technique: technique)
            }
            .listRowBackground(Color.clear)
        } else {
            Button {
                isShowingPaywall = true
            } label: {
                TechniqueRow(technique: technique, isLocked: true)
            }
            // Plain, so the row does not take the accent a button would and
            // start competing with the unlocked rows above it.
            .buttonStyle(.plain)
            .listRowBackground(Color.clear)
        }
    }
}

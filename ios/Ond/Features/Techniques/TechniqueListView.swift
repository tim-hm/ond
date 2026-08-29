import OndKit
import OndStyle
import OndUI
import SwiftUI

/// The whole catalogue, grouped by what each exercise is for. Its own root
/// rather than part of Home: someone reading about twelve exercises has come
/// here deliberately. The model arrives shared — three views onto one load.
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

    /// New, or nothing. Absent rather than disabled until the limits arrive
    /// and while the ceiling is reached: a `+` that does nothing when tapped
    /// is worse than no `+`, and the ceiling is explained on the exercise
    /// somebody would have to delete.
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

    /// The pill row, pinned under the title: a filtered list is short by
    /// definition, so a filter that scrolled away would be off screen exactly
    /// when it is most needed. Silent until the catalogue has landed — pills
    /// over a spinner narrow nothing, and pills over a failure compete with
    /// the retry button beside it.
    @ViewBuilder
    private var filters: some View {
        if case let .loaded(techniques) = model.state, !techniques.isEmpty {
            GoalFilterRow(goals: TechniqueGoal.present(in: techniques), selection: $goal)
        }
    }

    /// The exercises this person wrote. The group remains when empty so the
    /// New exercise row sits where its result will appear, and a failure is
    /// named in the same place — otherwise a first-run network failure would
    /// look exactly like an empty collection.
    private var ownSection: some View {
        LabelledSection(title: "Yours") {
            groupedRows {
                switch own.state {
                case .loading:
                    newExerciseRow

                case let .loaded(list):
                    let techniques = matching(list.techniques)
                    ForEach(Array(techniques.enumerated()), id: \.element.id) { index, technique in
                        NavigationLink(value: technique) {
                            TechniqueRow(technique: technique)
                        }

                        if index < techniques.count - 1 || own.hasRoomForAnother {
                            rowDivider
                        }
                    }

                    newExerciseRow

                case let .failed(message):
                    InlineRetry(message: message) {
                        Task { await own.load() }
                    }
                    .padding(.vertical, Theme.Spacing.close)
                }
            }
        }
    }

    /// A second, worded door to the toolbar's `+`, at the foot of the section
    /// it adds to — the glyph in chrome says nothing about what it makes.
    /// Absent on the same terms as that button: a row that opens nothing when
    /// the ceiling is reached would be worse than no row.
    @ViewBuilder
    private var newExerciseRow: some View {
        if own.hasRoomForAnother {
            Button {
                isComposing = true
            } label: {
                Label("New exercise", systemImage: "plus")
                    .font(.body)
                    .foregroundStyle(Theme.Accent.brandText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Theme.Spacing.standard)
            }
            .buttonStyle(.plain)
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
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        VStack(alignment: .leading, spacing: Theme.Spacing.loose) {
                            catalogueSection(of: matching(techniques))
                            ownSection
                            rhythmCaption
                        }
                        .padding(.horizontal, Theme.Spacing.page)
                        .padding(.top, Theme.Spacing.close)
                        .padding(.bottom, Theme.Spacing.loose)
                    } header: {
                        filters
                    }
                }
            }

        case let .failed(message):
            ReferenceRetryView(
                title: "Can't reach the catalogue",
                message: message
            ) {
                Task { await model.refresh() }
            }
        }
    }

    /// Every curated exercise, ordered by goal in one rounded group.
    ///
    /// The label belongs to the group rather than pinning repeatedly as goal
    /// sections scroll. Each row still carries its own goal and rhythm, so the
    /// grouping remains readable after filtering narrows it to one register.
    private func catalogueSection(of techniques: [Technique]) -> some View {
        let techniques = Self.ordered(techniques)

        return LabelledSection(title: "Curated") {
            groupedRows {
                ForEach(Array(techniques.enumerated()), id: \.element.id) { index, technique in
                    row(for: technique)

                    if index < techniques.count - 1 {
                        rowDivider
                    }
                }
            }
        }
    }

    /// One section plate. It keeps the rows on the palette ground because the
    /// goal word's contrast is measured there, while the line and shadow give
    /// the collection the native grouped composition of the reference.
    private func groupedRows(
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(spacing: 0, content: content)
            .padding(.horizontal, Theme.Spacing.standard)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .fill(Theme.Surface.ground.shadow(Theme.Shadow.list))
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .stroke(Theme.Surface.line, lineWidth: 0.5)
            }
    }

    private var rowDivider: some View {
        Divider().overlay(Theme.Surface.line)
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

    /// `techniques` narrowed to the active goal, or all of them. One rule for
    /// both sections, so a pill cannot thin the catalogue while leaving Yours
    /// intact — a filter that skipped them would be a filter that half worked.
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
    /// instead of the detail screen — listed at full strength, because
    /// somebody must still be able to read what they would be getting. The
    /// shipped catalogue reaches only the unlocked branch. The gate that
    /// holds is `SessionLaunchResolver`'s; this only decides which sheet opens.
    @ViewBuilder
    private func row(for technique: Technique) -> some View {
        if technique.isUnlocked(for: plus.tier) {
            NavigationLink(value: technique) {
                TechniqueRow(technique: technique)
            }
        } else {
            Button {
                isShowingPaywall = true
            } label: {
                TechniqueRow(technique: technique, isLocked: true)
            }
            // Plain, so the row does not take the accent a button would and
            // start competing with the unlocked rows above it.
            .buttonStyle(.plain)
        }
    }
}

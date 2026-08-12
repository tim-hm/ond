import OndKit
import OndStyle
import OndUI
import SwiftUI

/// The whole catalogue, grouped by what each exercise is for.
///
/// Its own root rather than part of home: someone who wants to breathe takes
/// what home's dial is pointing at, and someone who wants to read about nine
/// exercises has come here deliberately. The model arrives shared with home —
/// two views onto one load.
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

    /// Whether somebody tapped a locked exercise. Which one is not kept: there
    /// is one subscription, and the paywall says the same thing whichever row
    /// was tapped.
    @State private var isShowingPaywall = false

    /// Whether the composer is open on a new exercise. Editing an existing one
    /// happens from its detail screen, where the thing being edited is already
    /// on screen.
    @State private var isComposing = false

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

    /// The exercises this person wrote, above the catalogue — somebody who has
    /// written their own came back for it.
    ///
    /// Silent while loading and while there are none: an empty section
    /// explaining a feature is an advertisement, and the New button is already
    /// the invitation. A *failure* is not silent, though. Somebody whose
    /// exercises did not load would otherwise see a screen that looks exactly
    /// like one where they never wrote any.
    @ViewBuilder
    private var ownSection: some View {
        switch own.state {
        case .loading:
            EmptyView()

        case let .loaded(list) where !list.techniques.isEmpty:
            Section {
                ForEach(list.techniques) { technique in
                    NavigationLink(value: technique) {
                        TechniqueRow(technique: technique)
                    }
                    .listRowBackground(Color.clear)
                }
            } header: {
                ownHeader
            }

        case .loaded:
            EmptyView()

        case let .failed(message):
            Section {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Theme.Ink.secondary)
                Button("Try again") {
                    Task { await own.load() }
                }
                .font(.footnote)
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

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView()

        // Same guard as home: an empty catalogue is an answer worth naming,
        // not a blank list.
        case let .loaded(techniques) where techniques.isEmpty:
            ContentUnavailableView {
                Label("The catalogue is empty", systemImage: "wind")
            } description: {
                Text("The server answered, but with no exercises in it.")
            } actions: {
                Button("Try again") {
                    Task { await model.load() }
                }
            }

        case let .loaded(techniques):
            List {
                // Leads the catalogue rather than replacing it: somebody who
                // came here to browse still browses, and somebody who wants to
                // be told what to do is told first.
                SuggestedForYouView(techniques: techniques, assistant: assistant)

                ownSection

                catalogueSection(of: techniques)
            }
            .listStyle(.plain)

        case let .failed(message):
            ContentUnavailableView {
                Label("Can't reach the catalogue", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") {
                    Task { await model.load() }
                }
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
        }
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
    /// the catalogue is what Plus sells, so somebody has to be able to read what
    /// they would be getting. Dimming reads as a punishment for not having paid;
    /// a lock beside a name and a summary reads as an invitation, which is what
    /// this is.
    ///
    /// A locked exercise never reaches `SessionModel.starting`, but that gate is
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

private struct TechniqueRow: View {
    let technique: Technique
    var isLocked = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.close) {
            HStack(spacing: Theme.Spacing.close) {
                Text(technique.name)
                    .font(.headline)

                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        // The brand accent rather than a warning colour: the
                        // lock is the app offering something, not the app
                        // telling somebody off.
                        .foregroundStyle(Theme.Accent.brand)
                        .accessibilityLabel("Included with önd Plus")
                }
            }

            // Curated or written by the person reading it, both arrive here.
            // Empty where an author said nothing, and an empty `Text` is a
            // blank line rather than nothing.
            if !technique.summary.isEmpty {
                Text(technique.summary)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Ink.secondary)
            }

            technique.rowCaption
                .font(.caption)
        }
        .padding(.vertical, Theme.Spacing.close)
    }
}

private extension Technique {
    /// "relax · 8 cycles · 16s each". What the exercise is for, then the shape of
    /// it — the two things somebody choosing between nine of them is comparing.
    ///
    /// The goal leads because it is what the section header above this row used to
    /// say, and one word is all it ever needed: five headers' worth of type, folded
    /// into the line each row was already carrying.
    ///
    /// That word alone carries `goal.accent`; the facts after it stay in tertiary
    /// ink. The row used to stroke a figure at its far end in the same accent, but
    /// at row size the drawing was texture rather than information, so the word is
    /// now the accent's only carrier. Colouring the whole caption would spend it
    /// on cycle counts that mean nothing by it, and cost contrast on the half
    /// nobody needs colour for.
    ///
    /// Legible only because these rows are transparent over `paletteGround()`:
    /// `ThemeColorTests` measures the goal accents as small text on that ground,
    /// and they do not all clear AA on `Surface/Raised`. Put a card behind this row
    /// and the colour comes back out — `GoalBadge` is the treatment that survives
    /// a card.
    var rowCaption: Text {
        Text(goal.intentObject).foregroundStyle(goal.accent)
            + Text(" · \(shapeDescription)").foregroundStyle(Theme.Ink.tertiary)
    }

    /// "8 cycles · 16s each", or "3 rounds · you end the holds". The shape of
    /// the technique at a glance — and the staged ones are a different
    /// proposition from the cyclic ones, so they say so.
    var shapeDescription: String {
        guard !isStaged, let stage = stages.first else {
            let unit = recommendedRounds == 1 ? "round" : "rounds"
            return hasOpenEndedStage
                ? "\(recommendedRounds) \(unit) · you end the holds"
                : "\(recommendedRounds) \(unit) · \(stages.count) stages"
        }

        let seconds = stage.cycleDuration.components.seconds
        return "\(stage.cycles) cycles · \(seconds)s each"
    }
}

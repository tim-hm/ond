import OndKit
import OndStyle
import OndUI
import SwiftUI

/// What an exercise is, what it asks of you, how long you want to do it for,
/// and the way in.
struct TechniqueDetailView: View {
    /// The mutually exclusive sheets this detail screen can present.
    private enum PresentedSheet: String, Identifiable {
        /// The editor for a personal exercise.
        case edit
        /// The non-destructive dials for a catalogue exercise.
        case customise
        /// The composer seeded from a catalogue exercise.
        case copy

        var id: Self {
            self
        }
    }

    let technique: Technique

    /// The list an exercise somebody wrote is edited and deleted through. Held
    /// even for a curated technique, because the screen is one screen: which
    /// controls it shows is `technique.origin`'s answer, not the caller's.
    let own: UserTechniqueModel

    let sessions: any SessionRecording

    /// All three ride through to `TechniqueCoachDoor` and are only read there.
    /// The door is drawn for a catalogue technique only — the coach is briefed
    /// on the seeded ones — but the screen is one screen, so the dependencies
    /// ride along whichever origin it shows.
    let assistant: any AssistantReading
    let chats: any ConversationStoring
    let catalogue: TechniqueListModel

    @Environment(SessionSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @Environment(SubscriptionStore.self) private var plus

    @State private var launcher: StopLauncher

    @State private var presentedSheet: PresentedSheet?
    @State private var isConfirmingDelete = false
    @State private var deletionFailure: String?

    init(
        technique: Technique,
        own: UserTechniqueModel,
        sessions: any SessionRecording,
        assistant: any AssistantReading,
        chats: any ConversationStoring,
        catalogue: TechniqueListModel
    ) {
        self.technique = technique
        self.own = own
        self.sessions = sessions
        self.assistant = assistant
        self.chats = chats
        self.catalogue = catalogue
        _launcher = State(wrappedValue: StopLauncher(sessions: sessions))
    }

    var body: some View {
        // Derived once per pass and handed down: `dialled` walks the stored
        // preferences and rebuilds every stage, which is not work to repeat for
        // each section of one screen.
        let dialled = technique.dialled(with: settings.overrides(for: technique))

        ScrollView {
            // The shape of the exercise, how to do it, then the deeper reading
            // for whoever wants it.
            VStack(alignment: .leading, spacing: Theme.Spacing.loose) {
                BreathRhythmChart(technique: dialled)

                // `dialled` rather than the curated technique: the steps and the
                // dose count seconds, cycles and minutes, and those have to be
                // the ones the dials are set to.
                TechniquePractice(technique: dialled)

                aboutSection

                // Only for a catalogue exercise, the same rule the explanation
                // this replaced kept: the coach is briefed on the seeded
                // techniques and has nothing to say about one somebody wrote
                // this morning.
                if technique.origin == .catalogue {
                    TechniqueCoachDoor(
                        technique: technique,
                        assistant: assistant,
                        chats: chats,
                        catalogue: catalogue,
                        sessions: sessions
                    )
                }

                // Only the undo an exercise somebody wrote needs. Changing one
                // — dialling a curated exercise, editing an authored one — is
                // the corner's job now.
                if technique.origin == .personal {
                    deleteControl
                }
            }
            .padding(Theme.Spacing.standard)
        }
        .safeAreaInset(edge: .bottom) { beginBar }
        .paletteGround()
        // The exercise list kicks this off too, but this screen is reachable
        // without it — a notification, a home card, a coach offer — and the
        // limits it carries are what decide whether an exercise can be made
        // your own. Idempotent, so arriving the ordinary way costs nothing.
        .task { await own.loadIfNeeded() }
        .navigationTitle(technique.name)
        // Large, so the name is the heading of the thing just tapped and the
        // figure has something to sit under, collapsing into the bar on the way
        // down.
        .navigationBarTitleDisplayMode(.large)
        // The star inboard of the change button, so the corner people already
        // know stays the one that changes the exercise.
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { TechniqueStarButton(technique: technique) }
            ToolbarItem(placement: .topBarTrailing) { changeButton }
        }
        .stopLauncher(launcher)
        .sheet(item: $presentedSheet) { sheet in
            presented(sheet)
        }
        .confirmationDialog(
            "Delete \(technique.name)?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { Task { await delete() } }
        } message: {
            Text("It goes from every device. The sessions you have already done are kept.")
        }
        .alert(
            "Couldn't delete it",
            isPresented: Binding(get: { deletionFailure != nil }, set: { _ in
                deletionFailure = nil
            })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deletionFailure ?? "")
        }
    }

    /// The explanation and its evidence as equal topics in the app's shared
    /// reading hierarchy. A personal exercise has a description rather than a
    /// mechanism, and a curated fallback is described on the same honest terms.
    @ViewBuilder private var aboutSection: some View {
        let topics = aboutTopics
        if !topics.isEmpty {
            ReadingSection(title: "About this exercise", topics: topics)
        }
    }

    private var aboutTopics: [ReadingSection.Topic] {
        var topics: [ReadingSection.Topic] = []

        // First, and above the mechanism, because it is the only topic here that
        // is an instruction rather than an explanation: somebody who reads one
        // thing on this screen before tapping Begin should read the one that
        // changes what their body does.
        if let preparation = technique.preparationContent {
            topics.append(.init(
                id: "preparation",
                title: "Before you start",
                content: preparation
            ))
        }

        if let mechanism = technique.mechanismContent {
            topics.append(.init(id: "mechanism", title: "How it works", content: mechanism))
        } else if let description = technique.closingNote {
            topics.append(.init(
                id: "description",
                title: "Description",
                content: ReadingContent(lead: description)
            ))
        }

        if let evidence = technique.evidenceContent {
            topics.append(.init(
                id: "evidence",
                title: "Evidence",
                content: evidence,
                grade: technique.evidenceGrade
            ))
        }

        return topics
    }

    /// The one way to change this exercise, in the corner both origins share:
    /// a personal exercise is edited, a curated one is dialled — different
    /// sheets, never both, but the same corner should not mean two things on
    /// two screens that look alike. A curated exercise that can be copied has
    /// a second thing to offer and so becomes a menu.
    @ViewBuilder private var changeButton: some View {
        if canCopy {
            Menu {
                customiseButton
                Button("Make my own", systemImage: "plus") { presentedSheet = .copy }
            } label: {
                Label("Change", systemImage: "slider.horizontal.3")
            }
        } else if technique.origin == .personal {
            Button {
                presentedSheet = .edit
            } label: {
                Label("Edit", systemImage: "slider.horizontal.3")
            }
            // Absent limits means the list has not loaded and the composer has
            // nothing to bound its dials with.
            .disabled(own.limits == nil)
        } else {
            customiseButton
        }
    }

    /// Dialling, which a curated exercise offers whether or not it can also be
    /// copied — one spelling, because the menu and the bare corner are the same
    /// action reached two ways.
    private var customiseButton: some View {
        Button {
            presentedSheet = .customise
        } label: {
            Label("Customise", systemImage: "slider.horizontal.3")
        }
    }

    /// Whether this screen has a second thing to offer, and therefore a menu.
    /// What may be copied at all is `Technique.isCopyable`'s; this adds only
    /// room for the result, on the rule `TechniqueListView.composeButton`
    /// states, so a one-item menu collapses back to the plain button.
    private var canCopy: Bool {
        technique.isCopyable && own.hasRoomForAnother
    }

    /// Delete, for an exercise this person wrote.
    ///
    /// Left on the screen rather than folded in beside Edit: it is rare and it
    /// does not come back, and a destructive action does not belong behind the
    /// same tap as a stepper.
    private var deleteControl: some View {
        Button("Delete", role: .destructive) { isConfirmingDelete = true }
            .font(.footnote)
            .tapTarget()
    }

    private func delete() async {
        do {
            try await own.delete(technique)
            dismiss()
        } catch {
            deletionFailure = error.localizedDescription
        }
    }

    /// The way in, held at the bottom edge so a long page cannot scroll it
    /// away, over a material the reading passes under. The lock is
    /// `SessionLaunchResolver`'s to enforce — this screen only decides what
    /// the button says. A locked exercise should still read; the offer belongs
    /// at the moment somebody tries to breathe it.
    private var beginBar: some View {
        let isUnlocked = technique.isUnlocked(for: plus.tier)

        return Button {
            launcher.begin(DialStop.standingFor(
                technique,
                dialled: settings.overrides(for: technique)
            ))
        } label: {
            Text(isUnlocked ? "Begin" : "Unlock to breathe this")
        }
        .buttonStyle(.inkAction(minHeight: Theme.Metrics.leadActionHeight))
        // The page's own margin, not the wider one the other pinned actions
        // use, so the capsule's edges line up with the cards above it. The
        // material reaches the home indicator, or the reading would show
        // through the strip below the bar.
        .padding(.horizontal, Theme.Spacing.standard)
        .padding(.vertical, Theme.Spacing.close)
        .background(.regularMaterial, ignoresSafeAreaEdges: .bottom)
    }

    /// The destination for the one active sheet.
    @ViewBuilder
    private func presented(_ sheet: PresentedSheet) -> some View {
        switch sheet {
        case .edit:
            if let limits = own.limits {
                TechniqueComposerView(model: own, limits: limits, editing: technique)
            }
        case .customise:
            TechniqueDialsView(technique: technique)
        case .copy:
            if let limits = own.limits {
                TechniqueComposerView(model: own, limits: limits, basedOn: technique)
            }
        }
    }
}

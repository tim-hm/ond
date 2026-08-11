import OndKit
import OndStyle
import OndUI
import SwiftUI

/// Where somebody builds their own exercise: one or more rhythms in order, how
/// many times each repeats, what to call it, and what it is for.
///
/// A stage per section, because a sequence is what is being read as much as
/// edited — somebody chaining fast breaths into a long exhale wants both on
/// screen at once, not one behind a row they have to tap into. Stages are
/// reordered and removed from a menu on their own header rather than by dragging:
/// there is no edit mode on this screen, and a gesture that only works in one is
/// a gesture nobody finds.
///
/// Rounds appear only once there is more than one stage. With a lone stage a
/// round and a cycle are the same number said twice, which is why removing the
/// second-to-last stage puts rounds back to one rather than leaving a number the
/// screen has stopped showing.
///
/// Every control is bounded by `AuthoringLimits`, which comes from the server:
/// the durations are the catalogue's own seeded ranges, so a dial here cannot
/// reach a breath the seeded evidence does not support. The server checks the
/// same values again — this screen exists so that nobody is told no.
struct TechniqueComposerView: View {
    let model: UserTechniqueModel
    let limits: AuthoringLimits

    /// The exercise being edited, or nil when composing a new one. Also what
    /// decides whether saving creates or replaces.
    let editing: Technique?

    @Environment(\.dismiss) private var dismiss

    /// Home's shortlist, so a new exercise starts out on it. See `save()`.
    @Environment(StarredStopStore.self) private var stars

    @State private var draft: TechniqueDraft
    @State private var refusal: String?
    @State private var isSaving = false

    init(model: UserTechniqueModel, limits: AuthoringLimits, editing: Technique? = nil) {
        self.model = model
        self.limits = limits
        self.editing = editing
        _draft = State(
            initialValue: editing.map(TechniqueDraft.init(editing:))
                ?? Self.opening(within: limits)
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                TechniqueAboutSection(draft: $draft, limits: limits)

                ForEach($draft.stages) { $stage in
                    stageSection($stage)
                }

                sessionSection

                if let refusal {
                    Section {
                        Text(refusal)
                            .font(.footnote)
                            .foregroundStyle(Theme.Ink.secondary)
                    }
                }
            }
            .navigationTitle(editing == nil ? "New exercise" : "Edit exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(!isComplete || isSaving)
                }
            }
            .tint(draft.goal.accent)
        }
    }

    /// One stage: the breaths in the order they are taken, and how many times
    /// they repeat.
    ///
    /// A `List` row per phase rather than a canvas: what is being authored is an
    /// ordered list of two facts each, and every gesture for reordering and
    /// removing one already exists on a row.
    private func stageSection(_ stage: Binding<DraftStage>) -> some View {
        Section {
            ForEach(stage.phases) { $phase in
                // The lookup covers every phase of the draft these rows are
                // built from, so the fallback is unreachable rather than a
                // default worth choosing.
                phaseRow($phase, kind: kinds[$phase.wrappedValue.id] ?? .inhale)
            }
            .onDelete { offsets in
                // Never to nothing: an exercise with no breaths in it is not a
                // shorter exercise.
                guard stage.wrappedValue.phases.count > offsets.count else { return }
                stage.wrappedValue.phases.remove(atOffsets: offsets)
            }
            .onMove { source, destination in
                stage.wrappedValue.phases.move(fromOffsets: source, toOffset: destination)
            }

            if stage.wrappedValue.phases.count < limits.maxPhasesPerStage {
                addPhaseMenu(to: stage)
            }

            Stepper(value: stage.cycles, in: limits.cycleRange) {
                let cycles = stage.wrappedValue.cycles
                Text(cycles == 1 ? "1 cycle" : "\(cycles) cycles")
            }
        } header: {
            stageHeader(stage.wrappedValue.id)
        } footer: {
            Text(
                "\(stage.wrappedValue.phases.count) of \(limits.maxPhasesPerStage) breaths. "
                    + "Swipe a row to remove it."
            )
        }
    }

    /// What this stage is called, and — once there is more than one — the menu
    /// that moves or removes it. A lone stage is the whole exercise, so it is
    /// named for what it is rather than numbered, and there is nothing to
    /// reorder it against.
    @ViewBuilder
    private func stageHeader(_ id: DraftStage.ID) -> some View {
        if let position = position(of: id), draft.stages.count > 1 {
            HStack {
                Text("Stage \(position + 1)")
                Spacer()
                stageMenu(id, at: position)
            }
        } else {
            Text("One cycle")
        }
    }

    private func stageMenu(_ id: DraftStage.ID, at position: Int) -> some View {
        Menu {
            Button("Move up") { move(id, by: -1) }
                .disabled(position == 0)
            Button("Move down") { move(id, by: 1) }
                .disabled(position == draft.stages.count - 1)
            Button("Remove stage", role: .destructive) { remove(id) }
        } label: {
            Label("Move or remove stage \(position + 1)", systemImage: "ellipsis.circle")
                .labelStyle(.iconOnly)
        }
    }

    /// Three movements rather than four phase kinds. Which of the two holds a
    /// hold becomes follows from the breath before it, so it is derived on the
    /// way to the server rather than asked for here.
    private func addPhaseMenu(to stage: Binding<DraftStage>) -> some View {
        // The new phase goes on the end, so the hold it would derive to is
        // settled before the menu opens.
        let breath = lastBreath(before: stage.wrappedValue.id)

        return Menu("Add a breath") {
            ForEach(Movement.options, id: \.self) { movement in
                // A movement whose kind the catalogue seeds no range for is left
                // off entirely, rather than offered with a duration this screen
                // invented to fill the gap.
                if let range = limits.range(for: movement.kind(after: breath)) {
                    Button(movement.title) {
                        stage.wrappedValue.phases.append(
                            DraftPhase(movement: movement, duration: Self.opening(of: range))
                        )
                    }
                }
            }
        }
    }

    /// One phase: how the breath moves, how long for, and — where air is
    /// actually moving — where it goes.
    ///
    /// The passage selector is absent for a hold rather than disabled, because
    /// there is nothing to choose: air that is not moving goes nowhere, and a
    /// greyed-out control says the opposite.
    ///
    /// - Parameter kind: what this phase stores as, derived across the whole
    ///   draft, because it is what picks the dial's range.
    @ViewBuilder
    private func phaseRow(_ phase: Binding<DraftPhase>, kind: PhaseKind) -> some View {
        let range = limits.range(for: kind)

        Stepper(
            value: seconds(of: phase),
            in: (range?.lowerBound.seconds ?? 0) ... (range?.upperBound.seconds ?? 0),
            step: 0.5
        ) {
            LabeledContent(
                // The spoken form rather than the on-screen one, because a
                // composed cycle can put both holds in one list and
                // `instruction` renders them as the same word twice.
                kind.spokenInstruction,
                value: phase.wrappedValue.duration.counted
            )
        }
        // A kind with no seeded range has nothing safe to dial it to, which is
        // the server refusing it rather than this screen deciding.
        .disabled(range == nil)

        if let passage = phase.wrappedValue.movement.passage {
            Picker(
                "Through",
                selection: Binding(
                    get: { passage },
                    set: { phase.wrappedValue.movement = phase.wrappedValue.movement.through($0) }
                )
            ) {
                ForEach(Passage.allCases, id: \.self) { passage in
                    Text(passage.title).tag(passage)
                }
            }
        }
    }

    /// What every phase of the draft stores as, by the row it is rendered from.
    ///
    /// Keyed by phase id rather than by position, because that is what the rows
    /// are keyed by — a positional lookup would hand a row the kind of whichever
    /// phase now sits where it used to. Recomputed per body pass rather than
    /// held in state: it is a pure function of the draft, and a cached copy is
    /// one edit away from showing the dial of the wrong hold.
    private var kinds: [DraftPhase.ID: PhaseKind] {
        var kinds: [DraftPhase.ID: PhaseKind] = [:]
        for (stage, derived) in zip(draft.stages, draft.kinds) {
            for (phase, kind) in zip(stage.phases, derived) {
                kinds[phase.id] = kind
            }
        }
        return kinds
    }

    /// The last inhale or exhale up to the end of `stage`, which is what a hold
    /// appended to it would take its lungs state from.
    private func lastBreath(before stage: DraftStage.ID) -> PhaseKind? {
        guard let position = position(of: stage) else { return nil }
        return draft.kinds.prefix(position + 1).joined().last { !$0.isHold }
    }

    /// The session rather than any one stage: room for another, how many times
    /// round them all, and how long that comes to.
    private var sessionSection: some View {
        Section {
            if draft.stages.count < limits.maxStages {
                Button("Add a stage") {
                    draft.stages.append(Self.openingStage(within: limits))
                }
            }

            if draft.stages.count > 1 {
                Stepper(value: $draft.rounds, in: limits.roundRange) {
                    Text(draft.rounds == 1 ? "1 round" : "\(draft.rounds) rounds")
                }
            }
        } footer: {
            Text("About \(inWords(draft.plannedDuration)).")
        }
    }

    /// Whether there is an exercise here at all — a name, and a breath in every
    /// stage. The ranges cannot be broken by the controls above, so nothing else
    /// needs checking before the server sees it.
    private var isComplete: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.stages.isEmpty
            && draft.stages.allSatisfy { !$0.phases.isEmpty }
    }

    private func position(of id: DraftStage.ID) -> Int? {
        draft.stages.firstIndex { $0.id == id }
    }

    /// Swaps a stage with its neighbour. Resolved by id rather than by the
    /// position the menu was built at: the header owning the menu is rebuilt
    /// whenever the list changes under it, and a closure still holding the old
    /// position would move somebody else's stage.
    private func move(_ id: DraftStage.ID, by offset: Int) {
        guard let from = position(of: id) else { return }
        let to = from + offset
        guard draft.stages.indices.contains(to) else { return }

        draft.stages.swapAt(from, to)
    }

    private func remove(_ id: DraftStage.ID) {
        // An exercise with no stages is not a shorter exercise, the same way one
        // with no breaths is not.
        guard draft.stages.count > 1 else { return }
        draft.stages.removeAll { $0.id == id }

        // Back to a lone stage, where rounds and cycles are the same number
        // said twice — and where the stepper that could put this right has just
        // gone off screen.
        if draft.stages.count == 1 {
            draft.rounds = 1
        }
    }

    /// Stores the draft, and puts a brand new exercise on home's shortlist.
    ///
    /// Starring here is what stops home burying the thing somebody just wrote. Its
    /// bands run occasions, then Start here, then `yours`, so an authored exercise is
    /// dealt behind every seeded moment and rung — page two of the board, on the
    /// shipped catalogue — and a star is the one thing that reaches past that order.
    /// Doing it on creation rather than asking is the honest reading of having written
    /// one: nobody composes an exercise they would rather not find.
    ///
    /// New ones only. A star is somebody's to remove, and re-applying it on every edit
    /// would put back a card they had deliberately taken off the strip.
    private func save() async {
        isSaving = true
        defer { isSaving = false }

        var submitted = limits.clamping(draft)
        submitted.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        submitted.summary = draft.summary.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let stored = try await model.save(submitted, replacing: editing)

            if editing == nil {
                stars.star(DialStop.id(of: stored))
            }

            dismiss()
        } catch {
            // The server's own words. It names the phase it objected to, which
            // is the one thing a generic failure could not.
            refusal = error.localizedDescription
        }
    }

    /// Seconds rather than milliseconds, because `Stepper` steps in the units it
    /// displays and half a second is the smallest move worth making by hand.
    private func seconds(of phase: Binding<DraftPhase>) -> Binding<Double> {
        Binding(
            get: { phase.wrappedValue.duration.seconds },
            set: { phase.wrappedValue.duration = .milliseconds(Int(($0 * 1000).rounded())) }
        )
    }

    /// Where a phase's dial starts: the middle of its safe range, rounded to the
    /// half-second the stepper moves in, so the first tap is a small change
    /// rather than a correction of an extreme.
    private static func opening(of range: ClosedRange<Duration>) -> Duration {
        let middle = (range.lowerBound.seconds + range.upperBound.seconds) / 2
        return .milliseconds(Int((middle * 2).rounded() / 2 * 1000))
    }

    /// The exercise a blank composer opens on: one stage, and nothing else to
    /// dismiss before it is already a real exercise.
    private static func opening(within limits: AuthoringLimits) -> TechniqueDraft {
        TechniqueDraft(name: "", goal: .calm, stages: [openingStage(within: limits)])
    }

    /// A stage to start from, whether it is the first or the third: one breath
    /// in, one out, ten times. The simplest thing that is already a rhythm, so
    /// the first thing somebody does is adjust rather than assemble.
    private static func openingStage(within limits: AuthoringLimits) -> DraftStage {
        let phases = [Movement.inhale(through: .nose), .exhale(through: .nose)]
            .compactMap { movement -> DraftPhase? in
                guard let range = limits.range(for: movement.kind(after: nil)) else { return nil }
                return DraftPhase(movement: movement, duration: opening(of: range))
            }

        return DraftStage(phases: phases, cycles: 10)
    }

    private func inWords(_ duration: Duration) -> String {
        duration.formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated))
    }
}

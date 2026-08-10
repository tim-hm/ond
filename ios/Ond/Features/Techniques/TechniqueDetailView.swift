import OndKit
import OndStyle
import OndUI
import SwiftUI

/// What an exercise is, what it asks of you, how long you want to do it for,
/// and the way in.
struct TechniqueDetailView: View {
    let technique: Technique

    /// The list an exercise somebody wrote is edited and deleted through. Held
    /// even for a curated technique, because the screen is one screen: which
    /// controls it shows is `technique.origin`'s answer, not the caller's.
    let own: UserTechniqueModel

    let sessions: any SessionRecording

    /// All three ride through to `TechniqueHeader`'s coach door and are only ever
    /// read there: the assistant that answers, a conversation to write into, and
    /// the catalogue an offer in that conversation resolves its slug against.
    ///
    /// The door is drawn for a catalogue technique only — the coach is briefed on
    /// the seeded ones — but the screen is one screen, so the dependencies ride
    /// along whichever origin it shows.
    let assistant: any AssistantReading
    let chats: any ConversationStoring
    let catalogue: TechniqueListModel

    @Environment(SessionSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var started: StartedSession?

    @Environment(SubscriptionStore.self) private var plus

    @State private var isShowingPaywall = false
    @State private var isEditing = false
    @State private var isConfirmingDelete = false
    @State private var deletionFailure: String?

    var body: some View {
        @Bindable var settings = settings
        // Derived once per pass and handed down: `dialled` walks the stored
        // preferences and rebuilds every stage, which is not work to repeat for
        // each section of one screen.
        let dialled = technique.dialled(with: settings.overrides(for: technique))

        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.loose) {
                // How it works, how you do it, and the coach — everything to read,
                // above the picture. `dialled` rather than the curated technique:
                // the how-to counts cycles and minutes, and those have to be the
                // ones the dials below are set to.
                TechniqueHeader(
                    technique: dialled,
                    assistant: assistant,
                    chats: chats,
                    catalogue: catalogue,
                    sessions: sessions
                )

                BreathRhythmChart(technique: dialled)

                // An exercise somebody wrote is edited, not dialled. The two
                // are the same gesture with different durability — one syncs
                // and one does not — and offering both would leave a person
                // wondering which of their two numbers is the real one.
                if technique.origin == .personal {
                    ownControls
                } else {
                    advanced(of: dialled)
                }
            }
            .padding(Theme.Spacing.standard)
        }
        .paletteGround()
        // Begin sits above the tab bar rather than at the end of the content,
        // so the one action this screen exists for is always in reach. The
        // content scrolls under it.
        .safeAreaInset(edge: .bottom) { beginBar(playing: dialled) }
        .navigationTitle(technique.name)
        .navigationBarTitleDisplayMode(.inline)
        .paywall(highlighting: technique.requires, isPresented: $isShowingPaywall)
        .fullScreenCover(item: $started) { session in
            SessionView(model: session.model)
        }
        .sheet(isPresented: $isEditing) {
            if let limits = own.limits {
                TechniqueComposerView(model: own, limits: limits, editing: technique)
            }
        }
        .confirmationDialog(
            "Delete \(technique.name)?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { Task { await delete() } }
        } message: {
            Text("It goes from every device. The sessions you have already done stay.")
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

    /// Edit and delete, for an exercise this person wrote.
    ///
    /// No dose line of its own any more: the header states it for every exercise,
    /// authored or curated, so a second copy here would be the same sentence twice
    /// on the one screen that has no dials to explain the difference.
    private var ownControls: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.close) {
            Button("Edit") { isEditing = true }
                .buttonStyle(.bordered)
                .tint(technique.goal.accent)
                // Absent limits means the list has not loaded, and the composer
                // has nothing to bound its dials with.
                .disabled(own.limits == nil)

            Button("Delete", role: .destructive) { isConfirmingDelete = true }
                .font(.footnote)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
    }

    private func delete() async {
        do {
            try await own.delete(technique)
            dismiss()
        } catch {
            deletionFailure = error.localizedDescription
        }
    }

    /// Every dial there is, one tap out of the way: the phase lengths, how many
    /// cycles each stage runs, how many rounds of the whole thing, and the undo.
    ///
    /// The length control used to stand outside this group — a cycles stepper in
    /// headline type between the figure and Customise, with the same stepper
    /// repeated inside for staged techniques. Folded in, on the reading that the
    /// screen is now built around: above the figure is what the exercise *is*, and
    /// everything that changes it lives behind one word. The dose is still stated
    /// up there in prose, so the number is never hidden — only the control is.
    private func advanced(of dialled: Technique) -> some View {
        DisclosureGroup("Customise") {
            VStack(alignment: .leading, spacing: Theme.Spacing.loose) {
                // Rounds first, and only where there are stages to repeat: it
                // multiplies every stage below it, so it reads as the outer dial
                // it is rather than as one more control in the list.
                if technique.isStaged {
                    Stepper(value: roundsBinding, in: TechniqueOverrides.roundRange) {
                        Text(dialled.recommendedRounds == 1 ? "1 round"
                            : "\(dialled.recommendedRounds) rounds")
                    }
                }

                ForEach(Array(dialled.stages.enumerated()), id: \.offset) { index, stage in
                    VStack(alignment: .leading, spacing: Theme.Spacing.close) {
                        if technique.isStaged {
                            Text(stage.title(at: index, staged: true))
                                .font(.subheadline.weight(.semibold))
                        }

                        ForEach(
                            Array(stage.phases.enumerated()),
                            id: \.offset
                        ) { phaseIndex, phase in
                            phaseDial(stage: index, phase: phaseIndex, of: phase)
                        }

                        // Every stage that has a length, not only a staged
                        // technique's: this is where a cyclic exercise's one
                        // stepper lives now.
                        if !stage.openEnded {
                            cyclesStepper(of: dialled, stage: index)
                        }
                    }
                }

                Button("Reset") {
                    settings.setOverrides(nil, for: technique)
                }
                .font(.footnote)
                // Footnote type is a 16pt row on its own. The frame is what
                // makes the undo for a mis-dragged dial reachable by the hand
                // that mis-dragged it.
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .disabled(settings.overrides(for: technique) == nil)
            }
            .padding(.top, Theme.Spacing.close)
        }
        .tint(technique.goal.accent)
    }

    private func cyclesStepper(of dialled: Technique, stage: Int) -> some View {
        let cycles = dialled.stages[stage].cycles
        return Stepper(value: cyclesBinding(stage: stage), in: TechniqueOverrides.cycleRange) {
            Text(cycles == 1 ? "1 cycle" : "\(cycles) cycles")
        }
    }

    @ViewBuilder
    private func phaseDial(stage: Int, phase index: Int, of phase: Phase) -> some View {
        if phase.isAdjustable {
            Stepper(
                value: durationBinding(stage: stage, phase: index),
                in: phase.range.lowerBound.seconds ... phase.range.upperBound.seconds,
                step: 0.5
            ) {
                LabeledContent(phase.kind.instruction, value: inSeconds(phase.duration))
            }
        } else {
            // A hold the person ends has no dial, and a disabled stepper would
            // invite them to look for one.
            LabeledContent(phase.kind.instruction, value: "you decide")
                .foregroundStyle(Theme.Ink.secondary)
        }
    }

    /// Begin, or the offer that has to come first.
    ///
    /// The lock is `SessionModel.starting`'s to enforce — this screen only
    /// decides what the button says and which sheet to open. A person who
    /// arrives on a locked technique should still read about it, which is what
    /// the catalogue is for; the offer belongs at the moment they try to
    /// breathe it.
    private func beginBar(playing dialled: Technique) -> some View {
        let isUnlocked = technique.isUnlocked(for: plus.tier)

        return Button {
            guard let model = SessionModel.starting(
                dialled,
                for: plus.tier,
                cues: SessionCues(mode: settings.cueMode, strength: settings.hapticStrength),
                recorder: sessions
            ) else {
                isShowingPaywall = true
                return
            }

            started = StartedSession(model: model)
        } label: {
            Text(isUnlocked ? "Begin" : "Unlock to breathe this")
                .primaryActionLabel()
                // The ground, so the label inverts with the fill: an accent is
                // dark on white and light on near-black, and a prominent button
                // that kept white text would be unreadable in one of the two.
                .foregroundStyle(Theme.Surface.ground)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(technique.goal.accent)
        // Asymmetric, and the button's own size is why. It wears
        // `primaryActionLabel` at `.controlSize(.large)` — the one geometry every
        // screen-concluding action in the app has, which is not this screen's to
        // retune — so the only thing here that can be too big is the band around
        // it. A full inset on all four sides stood a 49pt control inside an 80pt
        // slab of material, immediately above the tab bar's own, and two stacked
        // bands is what read as an oversized button.
        .padding(.horizontal, Theme.Spacing.standard)
        .padding(.vertical, Theme.Spacing.close)
        // The same treatment the paywall's pinned bar uses: a material rather
        // than a ground, so the content passing underneath stays legible as it
        // goes.
        .background(.bar)
    }

    /// The person's own settings, or the catalogue's where they have none —
    /// resolved through the technique, so a preference whose shape no longer
    /// matches it can never be indexed by the dials below.
    private var stored: TechniqueOverrides {
        technique.resolving(settings.overrides(for: technique))
    }

    private func update(_ change: (inout TechniqueOverrides) -> Void) {
        var overrides = stored
        change(&overrides)
        settings.setOverrides(overrides, for: technique)
    }

    private var roundsBinding: Binding<Int> {
        Binding(get: { stored.rounds }, set: { rounds in update { $0.rounds = rounds } })
    }

    private func cyclesBinding(stage: Int) -> Binding<Int> {
        Binding(
            get: { stored.stageCycles[stage] },
            set: { cycles in update { $0.stageCycles[stage] = cycles } }
        )
    }

    /// Seconds rather than milliseconds, because `Stepper` steps in the units it
    /// displays and half a second is the smallest move worth making by hand.
    private func durationBinding(stage: Int, phase: Int) -> Binding<Double> {
        Binding(
            get: { Double(stored.phaseDurationsMs[stage][phase]) / 1000 },
            set: { seconds in
                update { $0.phaseDurationsMs[stage][phase] = Int((seconds * 1000).rounded()) }
            }
        )
    }

    private func inSeconds(_ duration: Duration) -> String {
        "\(duration.inSeconds)s"
    }
}

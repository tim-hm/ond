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

    /// All three ride through to `TechniqueCoachDoor` and are only ever read there:
    /// the assistant that answers, a conversation to write into, and the catalogue
    /// an offer in that conversation resolves its slug against.
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
    @State private var isCustomising = false
    @State private var isConfirmingDelete = false
    @State private var deletionFailure: String?

    var body: some View {
        @Bindable var settings = settings
        // Derived once per pass and handed down: `dialled` walks the stored
        // preferences and rebuilds every stage, which is not work to repeat for
        // each section of one screen.
        let dialled = technique.dialled(with: settings.overrides(for: technique))

        ScrollView {
            // The shape of the exercise, then how to do it, then the way to ask
            // about it, then why it works. This screen used to open on two
            // paragraphs of physiology and put the figure below the fold, which
            // answered a question nobody arrives with before the one they do.
            VStack(alignment: .leading, spacing: Theme.Spacing.loose) {
                BreathRhythmChart(technique: dialled)

                // `dialled` rather than the curated technique: the steps and the
                // dose count seconds, cycles and minutes, and those have to be
                // the ones the dials are set to.
                TechniquePractice(technique: dialled)

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

                background

                // Only the undo an exercise somebody wrote needs. Changing one
                // — dialling a curated exercise, editing an authored one — is
                // the corner's job now.
                if technique.origin == .personal {
                    deleteControl
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
        // The star inboard of the change button, so the corner people already
        // know stays the one that changes the exercise.
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { TechniqueStarButton(technique: technique) }
            ToolbarItem(placement: .topBarTrailing) { changeButton }
        }
        .paywall(highlighting: technique.requires, isPresented: $isShowingPaywall)
        .fullScreenCover(item: $started) { session in
            SessionView(model: session.model)
        }
        .sheet(isPresented: $isEditing) {
            if let limits = own.limits {
                TechniqueComposerView(model: own, limits: limits, editing: technique)
            }
        }
        .sheet(isPresented: $isCustomising) {
            TechniqueDialsView(technique: technique)
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

    /// Why it works, for whoever is still reading — last, and absent entirely
    /// where the catalogue never wrote one.
    ///
    /// Nil for every exercise somebody wrote: the composer does not ask an author
    /// for a mechanism, because inviting one to assert physiology is not
    /// something this app should do. Such an exercise ends on its dose line, with
    /// the description its author typed up in the practice block, which is where
    /// it is of use.
    @ViewBuilder private var background: some View {
        if let mechanism = technique.mechanism {
            Text(mechanism)
                .font(.body)
                .foregroundStyle(Theme.Ink.primary)
        }
    }

    /// The one way to change this exercise, in the corner both origins share.
    ///
    /// An exercise somebody wrote is edited and a curated one is dialled — the
    /// same gesture with different durability, one syncing and one not, which is
    /// why they open different sheets and never both. What they have in common
    /// is worth more than what separates them: two screens that look alike
    /// should not mean two different things by the same corner, and the screen
    /// below is then what the exercise *is*, with nothing on it that changes it.
    private var changeButton: some View {
        Button {
            if technique.origin == .personal {
                isEditing = true
            } else {
                isCustomising = true
            }
        } label: {
            Label(
                technique.origin == .personal ? "Edit" : "Customise",
                systemImage: "slider.horizontal.3"
            )
        }
        // Absent limits means the list has not loaded, and the composer has
        // nothing to bound its dials with. A curated exercise dials against the
        // catalogue's own ranges and never waits for anything.
        .disabled(technique.origin == .personal && own.limits == nil)
    }

    /// Delete, for an exercise this person wrote.
    ///
    /// Left on the screen rather than folded in beside Edit: it is rare and it
    /// does not come back, and a destructive action does not belong behind the
    /// same tap as a stepper.
    private var deleteControl: some View {
        Button("Delete", role: .destructive) { isConfirmingDelete = true }
            .font(.footnote)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
    }

    private func delete() async {
        do {
            try await own.delete(technique)
            dismiss()
        } catch {
            deletionFailure = error.localizedDescription
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
}

import OndKit
import OndStyle
import OndUI
import SwiftUI

/// Every dial a curated exercise has, one tap out of the way: the phase lengths,
/// how many cycles each stage runs, how many rounds of the whole thing, and the
/// undo.
///
/// A sheet off the corner of the exercise's own screen rather than a section at
/// the foot of it. The screen reads as what the exercise *is* — how it works,
/// how you do it, its figure — and everything that changes it now lives in one
/// place, the same corner an exercise somebody wrote is edited from.
///
/// Half height, and the page behind it stays live: `BreathRhythmChart` redraws
/// from the dialled exercise as a dial moves, and watching box breathing's
/// square stretch is the feedback that tells somebody what a number means. A
/// sheet that covered the figure would leave them setting numbers blind and
/// looking afterwards.
struct TechniqueDialsView: View {
    let technique: Technique

    @Environment(SessionSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        // Derived once per pass and read all the way down: `dialled` walks the
        // stored preferences and rebuilds every stage, which is not work to
        // repeat per control.
        let dialled = technique.dialled(with: settings.overrides(for: technique))

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.loose) {
                    // Rounds first, and only where there are stages to repeat: it
                    // multiplies every stage below it, so it reads as the outer
                    // dial it is rather than as one more control in the list.
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

                            ForEach(Array(stage.phases.enumerated()), id: \.offset) { phase, of in
                                phaseDial(stage: index, phase: phase, of: of)
                            }

                            // Every stage that has a length, not only a staged
                            // technique's: this is where a cyclic exercise's one
                            // stepper lives.
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
                .padding(Theme.Spacing.standard)
            }
            .navigationTitle("Customise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        // What keeps the figure watchable: the page underneath stays scrollable
        // at the short detent, so the drawing can be brought into view without
        // putting the dials away first.
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
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
                LabeledContent(phase.kind.instruction, value: "\(phase.duration.inSeconds)s")
            }
        } else {
            // A hold the person ends has no dial, and a disabled stepper would
            // invite them to look for one.
            LabeledContent(phase.kind.instruction, value: "you decide")
                .foregroundStyle(Theme.Ink.secondary)
        }
    }

    /// The person's own settings, or the catalogue's where they have none —
    /// resolved through the technique, so a preference whose shape no longer
    /// matches it can never be indexed by the dials above.
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
}

import OndKit
import OndStyle
import OndUI
import SwiftUI

/// Which question the gallery is currently asking.
///
/// One board at a time rather than one long scroll, because each of these is a
/// comparison and a comparison you have to scroll between is not one.
enum BreathFigureBoard: String, CaseIterable, Identifiable {
    /// Do the four phases read apart? All four run at once, so the answer does
    /// not depend on remembering the previous one.
    case phases
    /// Does it survive the screen it is for? The figure on the session player's
    /// own wash, with and without the ground put back under it.
    case player
    /// Does the figure say which nostril, and which asymmetry says it best?
    case nostrils
    /// Is it the same drawing from a session figure down to an Island cue?
    case scales
    /// Does it hold up on white as well as on near-black?
    case appearance

    var id: Self {
        self
    }

    var title: String {
        rawValue.capitalized
    }
}

/// All four phases at once, each on its own loop.
///
/// The board the design lives or dies on: box breathing gives every phase the
/// same length, so if these four are told apart it is by motion and nothing
/// else — which is the thing the monochrome switch is there to prove.
struct PhasesBoard: View {
    let elapsed: Duration
    let settings: BreathFigureSettings

    var body: some View {
        Grid(horizontalSpacing: Theme.Spacing.standard, verticalSpacing: Theme.Spacing.standard) {
            GridRow {
                cell(.inhale)
                cell(.holdIn)
            }
            GridRow {
                cell(.exhale)
                cell(.holdOut)
            }
        }
    }

    private func cell(_ kind: PhaseKind) -> some View {
        VStack(spacing: Theme.Spacing.close) {
            BreathFigureCell(
                loop: .alone(kind),
                elapsed: elapsed,
                settings: settings,
                size: 132
            )
            Text(kind.instruction)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.Ink.primary)
            Text(Self.envelope(of: kind))
                .font(.caption2)
                .foregroundStyle(Theme.Ink.secondary)
        }
    }

    /// What the envelope is doing, said in words, so a still screenshot of this
    /// board is still readable. Deliberately says nothing about the turn: the
    /// cadence treatment changes that and a caption cannot follow it.
    private static func envelope(of kind: PhaseKind) -> String {
        switch kind {
        case .inhale: "opening"
        case .holdIn: "wide, steady"
        case .exhale: "closing"
        case .holdOut: "tight, steady"
        }
    }
}

/// The figure on the ground it actually has to live on.
///
/// The session player washes its goal's accent over the ground, and the top of
/// that wash carries two legible marks where a figure needs four — so a figure
/// there gets `Theme.Surface.ground` put back underneath it. Both panels are
/// drawn, because the constraint is only believable as a comparison: the lower
/// one is what the figure looks like when nobody restores anything, and the
/// exhale is where it gives out first.
///
/// The panels hold the wash flat at `Theme.Wash.strongest` rather than running
/// the gradient down them, which is the one thing a small card cannot borrow
/// from the player: a `LinearGradient` maps to the frame it is drawn in, so a
/// 200-point card would compress the whole strongest-to-faintest sweep into
/// itself and stand the figure on the middle of it. Flat at the top of the wash
/// is both the worst case and the condition `ThemeColorTests` measures.
struct PlayerBoard: View {
    let elapsed: Duration
    let settings: BreathFigureSettings

    private static let figureSize: CGFloat = 148

    var body: some View {
        VStack(spacing: Theme.Spacing.loose) {
            panel("Ground restored", isGrounded: true)
            panel("Straight on the wash", isGrounded: false)
        }
    }

    @ViewBuilder
    private func panel(_ caption: String, isGrounded: Bool) -> some View {
        let figure = BreathFigureCell(
            loop: .box,
            elapsed: elapsed,
            settings: settings,
            size: Self.figureSize
        )

        VStack(spacing: Theme.Spacing.close) {
            if isGrounded {
                figure.figureGround()
            } else {
                figure
            }

            Text(caption)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.Ink.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.loose)
        .background(
            Theme.Surface.ground
                .overlay(settings.goal.accent.opacity(Theme.Wash.strongest))
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
    }
}

/// Alternate-nostril breathing, and the answers to how a figure says which side
/// the air is on.
///
/// They run together rather than behind a picker, because "does this read as a
/// side at all" is a question about the difference between them.
struct NostrilsBoard: View {
    let elapsed: Duration
    let settings: BreathFigureSettings

    var body: some View {
        VStack(spacing: Theme.Spacing.loose) {
            BreathFigureCell(
                loop: .alternate,
                elapsed: elapsed,
                settings: settings,
                size: 200
            )
            Text(instruction)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.Ink.primary)

            HStack(spacing: Theme.Spacing.close) {
                ForEach(BreathFigure.Bias.allCases, id: \.self) { bias in
                    VStack(spacing: Theme.Spacing.tight) {
                        BreathFigureCell(
                            loop: .alternate,
                            elapsed: elapsed,
                            settings: biased(towards: bias),
                            size: 80
                        )
                        Text(bias.rawValue)
                            .font(.caption2)
                            .foregroundStyle(Theme.Ink.secondary)
                    }
                }
            }
        }
    }

    /// "Breathe in, left nostril" — the sentence the player speaks, so the label
    /// and the drawing can be checked against each other.
    private var instruction: String {
        BreathLoop.alternate.moment(at: elapsed)?.beat.spokenInstruction ?? ""
    }

    private func biased(towards bias: BreathFigure.Bias) -> BreathFigureSettings {
        var settings = settings
        settings.configuration.bias = bias
        return settings
    }
}

/// The same instant of the same loop at four sizes, ending at the 22 points a
/// Dynamic Island cue gets.
///
/// The miniature is the same call as the full figure with a smaller number, which
/// is the claim being made: the Island's dot is this figure's seed rather than a
/// separate drawing that has to be kept in step.
struct ScalesBoard: View {
    let elapsed: Duration
    let settings: BreathFigureSettings

    var body: some View {
        VStack(spacing: Theme.Spacing.loose) {
            figure(at: 220)

            HStack(alignment: .center, spacing: Theme.Spacing.loose) {
                labelled(110, "wrist")
                labelled(56, "list row")
            }

            island
        }
    }

    /// The Island's own ground rather than the app's: the cue is drawn on the
    /// hardware's black cutout whatever the phone's appearance, so a figure that
    /// reads here in light mode has not been checked.
    ///
    /// Pinned to the dark appearance for the same reason the black is hard-coded.
    /// The cutout never renders light-mode ink, so a mock that inherited the
    /// phone's scheme would put the light variant of a goal accent on black — a
    /// pairing the real Island cannot produce, judged as though it could.
    private var island: some View {
        HStack(spacing: Theme.Spacing.close) {
            figure(at: 22)
            Text("4:44")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white)
        }
        .padding(.horizontal, Theme.Spacing.standard)
        .padding(.vertical, Theme.Spacing.close)
        .background(Capsule().fill(.black))
        .environment(\.colorScheme, .dark)
    }

    private func labelled(_ size: CGFloat, _ caption: String) -> some View {
        VStack(spacing: Theme.Spacing.tight) {
            figure(at: size)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(Theme.Ink.secondary)
        }
    }

    private func figure(at size: CGFloat) -> some View {
        BreathFigureCell(loop: .box, elapsed: elapsed, settings: settings, size: size)
    }
}

/// The same figure on both grounds at once.
///
/// Forced through the environment rather than by relaunching in the other
/// appearance, because the exhale's contrast is the regression this palette has
/// shipped twice and it is only ever visible in the comparison.
struct AppearanceBoard: View {
    let elapsed: Duration
    let settings: BreathFigureSettings

    var body: some View {
        VStack(spacing: Theme.Spacing.standard) {
            ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
                panel(scheme)
            }
        }
    }

    private func panel(_ scheme: ColorScheme) -> some View {
        HStack(spacing: Theme.Spacing.standard) {
            ForEach([PhaseKind.inhale, .exhale], id: \.self) { kind in
                VStack(spacing: Theme.Spacing.tight) {
                    BreathFigureCell(
                        loop: .alone(kind),
                        elapsed: elapsed,
                        settings: settings,
                        size: 104
                    )
                    Text(kind.instruction)
                        .font(.caption2)
                        .foregroundStyle(Theme.Ink.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.standard)
        .background(Theme.Surface.ground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .environment(\.colorScheme, scheme)
    }
}

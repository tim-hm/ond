import OndKit
import OndStyle
import OndUI
import SwiftUI

/// Everything the gallery can change about a figure, in one value so a board
/// takes one parameter rather than eight.
struct BreathFigureSettings {
    var configuration = BreathFigure.Configuration()
    var goal: TechniqueGoal = .calm
    var sideReading: BreathLoop.SideReading = .breath
    /// Draws every phase in one ink, which is how the claim "legible at a glance
    /// without colour" gets checked rather than asserted.
    var isMonochrome = false
    /// Reduce Motion, forced on regardless of the device — the setting is the
    /// one thing about this figure a simulator cannot be trusted to report.
    var isStilled = false
}

/// One loop, drawn at one size.
///
/// The whole of the per-frame work: read the moment off the loop, turn it into a
/// pose, hand the pose to the figure. No state, no animation modifier, nothing
/// that survives between frames — so pausing the clock above this really does
/// stop everything.
struct BreathFigureCell: View {
    let loop: BreathLoop
    let elapsed: Duration
    let settings: BreathFigureSettings
    let size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    var body: some View {
        let moment = loop.moment(at: elapsed, reading: settings.sideReading)

        BreathFigureView(pose: pose(at: moment), stroke: stroke(at: moment), size: size)
            .accessibilityHidden(true)
    }

    private var reduceMotion: Bool {
        settings.isStilled || systemReduceMotion
    }

    private func pose(at moment: BreathLoop.Moment?) -> BreathFigure.Pose {
        guard let moment else { return BreathFigure.seed(configuration: settings.configuration) }

        return BreathFigure.pose(
            for: moment.beat.breath,
            fullness: moment.fullness,
            progress: moment.progress,
            side: moment.side,
            reduceMotion: reduceMotion,
            configuration: settings.configuration
        )
    }

    /// The one line that turns a phase into ink. Monochrome takes the primary
    /// ink rather than a dimmed accent, so what is being tested is the motion
    /// with the colour language removed rather than the colour language turned
    /// down.
    private func stroke(at moment: BreathLoop.Moment?) -> Color {
        guard !settings.isMonochrome else { return Theme.Ink.primary }

        let kind = moment?.beat.kind ?? .holdOut
        return BreathFigure.ink(for: kind).colour(on: settings.goal.accent)
    }
}

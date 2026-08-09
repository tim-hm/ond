import OndKit
import OndUI
import SwiftUI

/// The whole cue: a dot that expands and contracts, inside a ring that sweeps
/// the phase it is in.
///
/// Two jobs, split because only one of them can be trusted. The dot says *which*
/// phase — full lungs are a big dot, empty ones a small one, exactly the number
/// the in-app orb scales by — and it changes only when a new snapshot arrives.
/// The ring says *where in the phase*, and the system interpolates it locally
/// from the phase's own window, so it keeps pace whether or not the next update
/// lands on time. A cue built on updates alone appears to work in the simulator
/// and then falls behind on a device; this one degrades to a completed ring and
/// a dot that is merely early, which still reads as the right phase.
///
/// Deliberately the smallest geometry that can carry a breath. TIM-129's figure
/// grows out of this rather than replacing it, so anything here that is not a
/// circle and a fraction is something that would have to be torn out.
struct BreathCue: View {
    let presence: SessionPresence
    let accent: Color
    /// The ring's diameter. The whole cue lays out at this size whatever the
    /// dot inside is doing, so a phase change never moves anything beside it.
    let diameter: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How much of the ring the dot fills at full lungs. Short of it on purpose:
    /// a dot that touched the ring would swallow the sweep at the top of every
    /// inhale, which is the moment the pace is most worth reading.
    private static let dotShare: CGFloat = 0.62
    private static let restingRing: CGFloat = 2.5

    var body: some View {
        ZStack {
            ring
            dot
        }
        .frame(width: diameter, height: diameter)
        // A picture of what the words beside it say. Every surface that shows
        // this also shows those, bar the Island's minimal presentation, which
        // labels the cue itself.
        .accessibilityHidden(true)
    }

    /// Slate blue while the breath is held, the goal's accent while it moves.
    ///
    /// The same shift the in-app orb makes and for the same reason: a hold is
    /// the one phase where nothing is scaling, so the colour is all that marks
    /// the change.
    private var tint: Color {
        presence.breath.kind.isHold ? Theme.Accent.still : accent
    }

    private var dot: some View {
        Circle()
            .fill(tint)
            .frame(width: diameter * Self.dotShare, height: diameter * Self.dotShare)
            .scaleEffect(presence.fullness)
            .animation(travel, value: presence.fullness)
    }

    /// The system's own timer ring, which fills across the phase with no update
    /// from the app at all — and a plain resting ring wherever there is no
    /// window to sweep, so the layout is the same shape in every state.
    @ViewBuilder
    private var ring: some View {
        if let window = presence.window, !reduceMotion {
            ProgressView(timerInterval: window, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.circular)
            .tint(accent)
        } else {
            Circle().stroke(accent.opacity(0.3), lineWidth: Self.restingRing)
        }
    }

    /// How long the dot has to reach the size this phase ends on.
    ///
    /// The time actually left rather than the phase's whole length, so a
    /// snapshot that lands late arrives at full lungs when the inhale ends
    /// instead of overshooting into the exhale. Easing rather than linear,
    /// matching the smoothstep `lungFullness` applies — a breath does not change
    /// pace at its boundaries.
    ///
    /// Nil under Reduce Motion, and nil while nothing is moving: the dot then
    /// steps straight to its size, which is a state change rather than an
    /// animation, and the phase is still legible from it.
    ///
    /// Widgets are free to clamp a long animation. Where that bites, the ring
    /// above is what still carries the pace, which is why this is the half that
    /// was allowed to be uncertain.
    private var travel: Animation? {
        guard !reduceMotion, let window = presence.window else { return nil }
        let remaining = window.upperBound.timeIntervalSinceNow
        guard remaining > 0 else { return nil }
        return .easeInOut(duration: remaining)
    }
}

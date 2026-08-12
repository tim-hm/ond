import OndUI
import SwiftUI

/// The marketing site's orb: a filled dot inside two rings, breathing whether
/// or not anyone has begun.
///
/// It breathes briskly and visibly — a second and a half in, the same out —
/// with enough travel that the expansion reads as a breath rather than a
/// shimmer. Ambience, not instruction: the session orb swells to be
/// followed; this one only has to be unmistakably alive.
///
/// Scenery, and only ever that: it is drawn on the welcome screen and never
/// touched, which is why nothing here answers a finger.
struct AmbientOrb: View {
    /// What colour to breathe in. The brand accent, because nothing on the
    /// welcome screen belongs to a technique yet.
    let accent: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The one thing in the app that reads the appearance directly rather than
    /// through a token, and the reason is that alpha is not a colour: the same
    /// opacity that reads as a lit glow over the near-black ground washes
    /// towards the paper over the white one, worst on the warm accents. The
    /// palette carries a value per appearance and cannot carry an alpha, so the
    /// core's own alphas are what have to know. Dark keeps exactly the numbers
    /// it shipped with.
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // Built out here rather than in the closure below, which runs at display
        // refresh: nothing about the colours depends on the time, and the only
        // thing that does is the one number the three scales share.
        let core = RadialGradient(
            colors: [accent.opacity(coreAlpha.centre), accent.opacity(coreAlpha.edge)],
            center: .center,
            startRadius: 4,
            endRadius: 82
        )
        let outerRing = accent.opacity(0.15)
        let innerRing = accent.opacity(0.3)

        // A three-second cosine with 11% travel is drawn no better at 120 Hz
        // than at 30, and this one only has to be alive in the corner of an eye
        // — see `Theme.Motion.restfulFrameInterval`.
        return TimelineView(.animation(
            minimumInterval: Theme.Motion.restfulFrameInterval,
            paused: reduceMotion
        )) { context in
            let clock = context.date.timeIntervalSinceReferenceDate
            let breath = reduceMotion ? 1.0 : AmbientBreath.fullness(at: clock)
            let travel = 0.11 * breath

            // Bases sit `travel` short of where the old ones did, so a full
            // inhale lands the outer ring exactly on the frame's edge.
            ZStack {
                Circle()
                    .stroke(outerRing, lineWidth: 1)
                    .scaleEffect(0.89 + travel)

                Circle()
                    .stroke(innerRing, lineWidth: 1)
                    .scaleEffect(0.70 + travel)

                Circle()
                    .fill(core)
                    .scaleEffect(0.47 + travel)
            }
        }
        .frame(width: 176, height: 176)
        // Ambience, not information: nothing here is worth a VoiceOver stop.
        .accessibilityHidden(true)
    }

    /// What the core's radial gradient runs between, at each end.
    private var coreAlpha: (centre: Double, edge: Double) {
        colorScheme == .dark ? (centre: 0.7, edge: 0.15) : (centre: 0.95, edge: 0.45)
    }
}

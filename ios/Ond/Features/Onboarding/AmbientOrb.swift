import OndUI
import SwiftUI

/// The welcome's first guided breath: a real Coherent 5.5 cadence before the
/// flow asks anything of the person reading it.
///
/// This keeps the welcome geometry deliberately simpler than a session — two
/// rings and a core, with no halo or hold mark — while sharing the session's
/// phase-led premise. The clock begins when this view appears, so returning to
/// Welcome starts another complete inhale rather than landing at an arbitrary
/// point in a process-wide ambient loop.
struct AmbientOrb: View {
    /// What colour to breathe in. The brand accent, because nothing on the
    /// welcome screen belongs to a technique yet.
    let accent: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The cadence's local zero. A state value gives a rebuilt Welcome screen a
    /// fresh breath, which is also what makes the entrance replay on Back.
    @State private var startedAt = Date.now

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

        // An eleven-second breath is drawn no better at 120 Hz than at 30 — see
        // `Theme.Motion.restfulFrameInterval`.
        return TimelineView(.animation(
            minimumInterval: Theme.Motion.restfulFrameInterval,
            paused: reduceMotion
        )) { context in
            let breath = reduceMotion ? WelcomeBreath.still : WelcomeBreath(
                elapsed: max(0, context.date.timeIntervalSince(startedAt))
            )
            let travel = 0.11 * breath.fullness

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

                Text(breath.instruction)
                    .displaySerif(size: 30)
                    .foregroundStyle(Theme.Ink.primary)
                    .contentTransition(.opacity)
            }
        }
        .frame(width: 220, height: 220)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Guided breath")
        .accessibilityValue(
            reduceMotion ? "Breathe in" : "Breathing in and out for five and a half seconds each"
        )
    }

    /// What the core's radial gradient runs between, at each end.
    private var coreAlpha: (centre: Double, edge: Double) {
        colorScheme == .dark ? (centre: 0.7, edge: 0.15) : (centre: 0.95, edge: 0.45)
    }
}

/// One frame of the welcome cadence. Its phase and travel are kept together so
/// the word cannot turn before the drawing does.
private struct WelcomeBreath {
    private static let cycleDuration = AmbientBreath.restingCycle
    private static let phaseDuration = cycleDuration / 2

    let fullness: Double
    let instruction: String

    static let still = WelcomeBreath(fullness: 0.5, instruction: "Breathe in")

    init(elapsed: TimeInterval) {
        let position = elapsed.truncatingRemainder(dividingBy: Self.cycleDuration)
        let isInhaling = position < Self.phaseDuration
        let raw = (isInhaling ? position : position - Self.phaseDuration) / Self.phaseDuration
        let eased = raw * raw * (3 - 2 * raw)

        fullness = isInhaling ? eased : 1 - eased
        instruction = isInhaling ? "Breathe in" : "Breathe out"
    }

    private init(fullness: Double, instruction: String) {
        self.fullness = fullness
        self.instruction = instruction
    }
}

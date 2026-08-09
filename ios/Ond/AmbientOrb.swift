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
/// The welcome screen shows it as scenery and the home screen shows the same
/// orb as its one control, which is what `Role` decides. A control keeps both
/// rings at one weight so the shape reads as a target rather than a halo, and
/// it answers a finger by going still and lighting a ring. Both of those are
/// deliberately outside the channel the breath uses: a press that only changed
/// the orb's size would be arguing with an 11% swing that never stops, at less
/// than half its amplitude, and would lose.
struct AmbientOrb: View {
    /// What the orb is being asked to be. `scenery` is one thing and the other
    /// three are the control's three moments, so nothing is drawn that the
    /// moment does not need.
    enum Role {
        /// The welcome screen's orb, which breathes and is never touched.
        case scenery
        /// The home screen's control, at rest.
        case control
        /// A finger is on the control: the breath's clock stops and the ring
        /// lights.
        case held
        /// The finger has lifted and the session has not opened yet. The orb
        /// stays still and the ring leaves outwards, which is the beat that
        /// says the tap was taken.
        case taken
    }

    /// What colour to breathe in. The welcome screen hands it the brand accent,
    /// because nothing there belongs to a technique yet.
    let accent: Color

    /// Which of the four the orb is. Defaulted to scenery, so a caller that has
    /// no press to report does not have to say so.
    var role: Role = .scenery

    /// Whether the orb breathes at rest. Defaulted to true, which is every
    /// screen that shipped.
    ///
    /// False parks it at the top of an inhale — the same shape Reduce Motion
    /// has always been given, so this adds a caller for a state the orb could
    /// already draw rather than a second still pose. What it is for is a screen
    /// with something else moving on it: on the dial the breath and the ticking
    /// picker are two ambiences competing for the same corner of an eye, and
    /// the one that answers a finger should win.
    var breathes = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The one thing in the app that reads the appearance directly rather than
    /// through a token, and the reason is that alpha is not a colour: the same
    /// opacity that reads as a lit glow over the near-black ground washes
    /// towards the paper over the white one, worst on the warm accents. The
    /// palette carries a value per appearance and cannot carry an alpha, so the
    /// core's own alphas are what have to know. Dark keeps exactly the numbers
    /// it shipped with.
    @Environment(\.colorScheme) private var colorScheme

    /// When the breath's clock was stopped, or `nil` while it is running.
    @State private var stoppedAt: Date?

    /// How long the clock has been stopped for in total, subtracted from the
    /// live one so a resumed breath carries on from where it paused.
    @State private var stoppedFor: TimeInterval = 0

    /// One breath, in seconds.
    private static let cycle = 3.0

    /// How long the ring takes to leave once the tap is taken. Read by the
    /// control that owns the press so it waits exactly this long before opening
    /// the session — one number rather than two free to drift apart.
    static let acknowledgement: TimeInterval = 0.32

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
        // A control carries its outer ring at the inner one's weight, so the
        // two read as a deliberate pair around a core — the shape of a target,
        // which is as close to saying "press me" as this screen gets without
        // chrome. Scenery keeps the halo it had, fading outwards.
        let outerRing = accent.opacity(role == .scenery ? 0.15 : 0.3)
        let innerRing = accent.opacity(0.3)

        // Thirty a second rather than the display's own rate: this is the app's
        // resting screen, and a three-second cosine with 11% travel is drawn no
        // better at 120 Hz than at 30 — it only keeps the display pipeline awake
        // four times as often for it. The session orb is deliberately left
        // uncapped: that one is being followed breath for breath, and this one
        // only has to be alive in the corner of an eye.
        return TimelineView(
            .animation(minimumInterval: 1.0 / 30, paused: reduceMotion || isStill)
        ) { context in
            let clock = (stoppedAt ?? context.date).timeIntervalSinceReferenceDate - stoppedFor
            let breath = reduceMotion || !breathes ? 1.0 : fullness(at: clock)
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
        // Outside the timeline closure on purpose: the ring only matters while
        // the clock is stopped, so it has no reason to be rebuilt thirty times
        // a second at rest — which it was, transparent, and was exactly the
        // budget the cadence cap had bought back.
        .overlay {
            if role != .scenery {
                pressRing(at: frozenScale)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: accent)
        .onChange(of: isStill) { _, still in stopClock(still) }
        // Ambience, not information: nothing here is worth a VoiceOver stop.
        .accessibilityHidden(true)
    }

    /// Whether the breath is stopped: this orb never breathes, a finger is on
    /// it, or the tap has been taken and the session is on its way.
    private var isStill: Bool {
        !breathes || role == .held || role == .taken
    }

    /// Where the breath stopped, read off the frozen clock — the press ring
    /// has to land exactly on the outer ring, and outside the timeline closure
    /// this is the only way to know where that is. While the clock runs the
    /// ring is transparent, so the momentary value does not matter.
    private var frozenScale: CGFloat {
        let clock = (stoppedAt ?? .now).timeIntervalSinceReferenceDate - stoppedFor
        return 0.89 + 0.11 * (reduceMotion || !breathes ? 1.0 : fullness(at: clock))
    }

    /// The answer to a finger, in the one channel the breath leaves alone: a
    /// definite ring drawn over the outer one, at whatever scale the breath
    /// stopped it. Mounted across the control's three moments rather than
    /// inserted per press, so a press that is answered and then retracted —
    /// a finger dragged off the orb — still fades out instead of popping off.
    ///
    /// Taking the tap sends it outwards and fades it, which is what fills the
    /// beat between the finger lifting and the session arriving. Reduce Motion
    /// gets the fade without the travel — the ring is opacity either way, so a
    /// press is still answered where the scale it replaced was suppressed.
    private func pressRing(at scale: CGFloat) -> some View {
        Circle()
            .stroke(accent.opacity(0.85), lineWidth: 2)
            .scaleEffect(role == .taken && !reduceMotion ? 1.1 : scale)
            .opacity(role == .held ? 1 : 0)
            // Quick to re-light and slow to leave: a press landing on a ring
            // still rippling out re-answers inside the same moment as the
            // haptic, and the ripple itself is the acknowledgement rather
            // than a reaction.
            .animation(.easeOut(duration: role == .held ? 0.12 : Self.acknowledgement), value: role)
    }

    /// Stops the breath's clock while the orb is held, and adds the time it
    /// stood still when it is released.
    ///
    /// Accumulating the stopped time rather than easing back to the live clock
    /// is what makes both edges seamless: `fullness` reads a clock that simply
    /// did not run, so there is no value to interpolate towards on release and
    /// no jump to hide. It also means a finger stops the breath wherever it
    /// happens to be, which is the point — a living thing going still under a
    /// hand, not a pose it snaps to.
    private func stopClock(_ stopped: Bool) {
        if stopped {
            stoppedAt = .now
        } else if let stoppedAt {
            stoppedFor += Date.now.timeIntervalSince(stoppedAt)
            self.stoppedAt = nil
        }
    }

    /// What the core's radial gradient runs between, at each end.
    private var coreAlpha: (centre: Double, edge: Double) {
        colorScheme == .dark ? (centre: 0.7, edge: 0.15) : (centre: 0.95, edge: 0.45)
    }

    /// How full the lungs are, 0...1, on a cosine so the turn at full and at
    /// empty is soft — the same reason the session orb smoothsteps.
    private func fullness(at time: TimeInterval) -> Double {
        let progress = time.truncatingRemainder(dividingBy: Self.cycle) / Self.cycle
        return 0.5 - 0.5 * cos(progress * 2 * .pi)
    }
}

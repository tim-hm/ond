import OndKit
import WatchKit

/// The wrist breathing with you: each breath as a sustained purr of ticks
/// that tails off across the phase, each hold as one solid vibration.
///
/// The watch's answer to the phone's `HapticController`, and a deliberately
/// poorer one — watchOS has no CoreHaptics, so a phase cannot be shaped, only
/// marked. Every decision lives in OndKit where host tests pin it: `WatchCue`
/// says which phases purr, `WatchHapticStyle` shapes the curve and weighs the
/// taps for the chosen strength. This type is the half that can only be
/// judged on a wrist, so it maps abstract weights onto `WKHapticType` and
/// plays the schedule, nothing more.
///
/// Nothing to prepare: `WKInterfaceDevice` plays a tap with no engine behind
/// it to warm up or leak. The one thing to release is `pending` — a purr
/// mid-phase — which pause and stop cancel so the wrist goes quiet the
/// moment it is asked to.
@MainActor
final class WatchHapticController: SessionCueing {
    /// Read on every cue rather than resolved at composition, so a switch
    /// flicked between choosing a technique and finishing it takes effect on
    /// the next boundary instead of the next session.
    private let settings: WatchSettings

    init(settings: WatchSettings) {
        self.settings = settings
    }

    /// The wrist keeps tapping with the screen dark, which is the posture these
    /// techniques are actually done in. `ExtendedRuntime` is what buys that, and
    /// the watch player holds one for as long as the session lasts.
    let playsInBackground = true

    func prepare() {}

    /// The wrist's runtime is `ExtendedRuntime`'s to hold and the player's to
    /// end, and a pause is not the session ending — all a pause owes is
    /// silence, so it only cancels a purr still in flight.
    func pause() {
        pending?.cancel()
    }

    /// Resuming mid-phase deliberately does not re-fire a cue, and a purr the
    /// pause cancelled stays lost until the next boundary: reinstating it
    /// would need the beat's remaining time, which `SessionCueing` does not
    /// carry. A known cost, accepted over re-announcing a breath mid-flow.
    func resume() {}

    func play(_ beat: SessionTimeline.Beat) {
        pending?.cancel()

        // The seam between stages, which the phone rings a bell for and the
        // wrist has no way to sound. `.notification` rather than one of the
        // breath's own taps: it should read as the practice changing shape
        // rather than as an unusually emphatic breath.
        if beat.opensStage, settings.playsHaptics {
            WKInterfaceDevice.current().play(.notification)
        }

        let cue = WatchCue(beat.kind)
        // An open-ended beat's duration is a typical figure, never a schedule
        // (`SessionTimeline.Beat.isOpenEnded`), so nothing may purr over it.
        // No open-ended stage breathes today, but that is the catalogue's
        // fact, not this file's invariant.
        if cue.sustains, !beat.isOpenEnded {
            sustain(cue, for: beat.duration)
        } else {
            play(cue)
        }
    }

    func playCompletion() {
        pending?.cancel()
        play(.complete)
    }

    func stop() {
        pending?.cancel()
    }

    /// One discrete tap per cue: a breath's directional announcement (its
    /// purr is `sustain`'s), a hold's single vibration, completion's system
    /// pattern.
    private func play(_ cue: WatchCue) {
        guard settings.playsHaptics else { return }

        let haptic: WKHapticType = switch cue {
        case .rise: .directionUp
        case .fall: .directionDown
        case .mark: haptic(for: style.tap(for: cue))
        case .complete: .success
        }

        WKInterfaceDevice.current().play(haptic)
    }

    /// The wrist's breath: one directional announcement, then the purr
    /// `WatchHapticStyle` scheduled — dense at the turn of the breath,
    /// tailing off toward its end, ticking heavier on the way in than out.
    ///
    /// Ticks sleep to absolute deadlines so a wake-up the system delayed
    /// cannot stretch the train; a deadline the delay swallowed is skipped,
    /// not replayed, so it cannot bunch the train up either.
    private func sustain(_ cue: WatchCue, for duration: Duration) {
        guard settings.playsHaptics else { return }

        play(cue)

        let style = style
        let tick = haptic(for: style.tap(for: cue))
        let offsets = style.purr(over: duration)
        guard !offsets.isEmpty else { return }

        let clock = ContinuousClock()
        let start = clock.now
        pending = Task { [settings] in
            for offset in offsets {
                let deadline = start.advanced(by: offset)
                try? await clock.sleep(until: deadline, tolerance: Self.tickTolerance)
                // `try?` swallows the CancellationError, so cancellation is
                // re-checked explicitly whichever way the sleep ended.
                guard !Task.isCancelled else { return }
                // `continue`, not `return`: the switch is read per tick and
                // must work in both directions mid-phase, and a tick owed to
                // the past would land bunched against its neighbours.
                guard settings.playsHaptics,
                      clock.now < deadline + Self.tickForgiveness else { continue }
                WKInterfaceDevice.current().play(tick)
            }
        }
    }

    /// Slop the kernel may use to coalesce a tick's wake-up with the session's
    /// other timers — imperceptible against gaps of 60–340 ms, and ~20 fewer
    /// forced interrupts per phase with the screen dark.
    private static let tickTolerance: Duration = .milliseconds(20)

    /// How stale a tick may be and still play. Beyond this the wake-up missed
    /// its slot; playing it would stack it against the next one.
    private static let tickForgiveness: Duration = .milliseconds(100)

    /// Resolved per cue, not at composition, for the same reason `settings`
    /// is read per cue: a strength changed mid-session takes effect on the
    /// next boundary.
    private var style: WatchHapticStyle {
        WatchHapticStyle(strength: settings.hapticStrength)
    }

    /// The hardware's word for each abstract weight. `.stop` rather than
    /// `.notification` for prominent: its two solid taps read as heavy
    /// without the alert sound the notification types carry.
    private func haptic(for tap: WatchHapticStyle.Tap) -> WKHapticType {
        switch tap {
        case .soft: .click
        case .solid: .start
        case .prominent: .stop
        }
    }

    /// The purr still in flight, if any. Every entry point supersedes or
    /// cancels it, so at most one is ever alive.
    private var pending: Task<Void, Never>?
}

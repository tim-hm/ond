import OndKit
import WatchKit

/// The wrist breathing with you: a directional boundary, sparse solid pulses
/// tracing the phone's authored envelope, and a distinct cue per hold. A
/// deliberately poorer `HapticController` — watchOS has no CoreHaptics, so
/// amplitude becomes pulse density; the plan lives in OndKit where host tests
/// pin it. No engine to prepare; pause and stop cancel `pending`, the one thing live.
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
    /// silence, so it cancels every delayed cue and pulse still in flight.
    func pause() {
        pending?.cancel()
    }

    /// Resuming mid-phase deliberately does not re-fire a cue, and a train the
    /// pause cancelled stays lost until the next boundary: reinstating it
    /// would need the beat's remaining time, which `SessionCueing` does not
    /// carry. A known cost, accepted over re-announcing a breath mid-flow.
    func resume() {}

    func play(_ beat: SessionTimeline.Beat) {
        pending?.cancel()

        guard settings.playsHaptics else { return }

        if beat.opensStage {
            WKInterfaceDevice.current().play(beat.opensRound ? .start : .notification)
        }

        let cue = WatchCue(beat.kind)
        let cueDelay = beat.opensStage ? Self.seamGap : .zero
        let offsets = beat.isOpenEnded
            ? []
            : style.pulses(for: beat, cueDelay: cueDelay)

        if cueDelay == .zero {
            playImmediately(cue)
        }
        schedule(cue, after: cueDelay, pulsesAt: offsets)
    }

    func playCompletion() {
        pending?.cancel()
        playImmediately(.complete)
    }

    func stop() {
        pending?.cancel()
    }

    /// Plays a phase boundary without creating or superseding a schedule.
    private func playImmediately(_ cue: WatchCue) {
        guard settings.playsHaptics else { return }

        let haptic: WKHapticType = switch cue {
        case .rise: .directionUp
        case .fall: .directionDown
        case .holdIn, .holdOut:
            style.holdTap(for: cue).map(haptic(for:)) ?? .click
        case .complete: .success
        }

        WKInterfaceDevice.current().play(haptic)
    }

    /// Plays a delayed phase cue (`cueDelay` reserves room for a seam cue
    /// already played) and its sparse pulses, at `offsets` from the beat
    /// boundary, on one clock. Pulses sleep to absolute deadlines so a
    /// delayed wake-up cannot stretch the train; a deadline the delay
    /// swallowed is skipped, not replayed, so it cannot bunch up either.
    private func schedule(_ cue: WatchCue, after cueDelay: Duration, pulsesAt offsets: [Duration]) {
        guard cueDelay > .zero || !offsets.isEmpty else { return }

        let clock = ContinuousClock()
        let start = clock.now
        pending = Task { [settings] in
            if cueDelay > .zero {
                let cueDeadline = start.advanced(by: cueDelay)
                try? await clock.sleep(until: cueDeadline, tolerance: Self.tickTolerance)
                guard !Task.isCancelled else { return }
                guard settings.playsHaptics,
                      clock.now < cueDeadline + Self.tickForgiveness else { return }
                playImmediately(cue)
            }

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
                WKInterfaceDevice.current().play(Self.breathPulse)
            }
        }
    }

    /// Separation between a protocol seam and its arriving phase cue. The pulse
    /// plan adds its own 300 ms lead after this, so neither pattern overlaps.
    private static let seamGap: Duration = .milliseconds(350)

    /// Slop the kernel may use to coalesce a pulse's wake-up with the session's
    /// other timers, small against the 500–850 ms shaped gaps.
    private static let tickTolerance: Duration = .milliseconds(20)

    /// How stale a pulse may be and still play. Beyond this the wake-up missed
    /// its slot; playing it would stack it against the next one.
    private static let tickForgiveness: Duration = .milliseconds(100)

    private let style = WatchHapticStyle()

    /// The hardware's word for each abstract hold weight.
    private func haptic(for tap: WatchHapticStyle.Tap) -> WKHapticType {
        switch tap {
        case .soft: .click
        case .solid: .start
        }
    }

    /// The fixed click is too faint to carry a breath on current watch hardware.
    /// `.start` is the next compact non-alerting pattern and remains distinct
    /// from the directional boundary that announces the phase.
    private static let breathPulse: WKHapticType = .start

    /// The delayed cue and pulse train still in flight, if any. Every entry
    /// point supersedes or cancels it, so at most one is ever alive.
    private var pending: Task<Void, Never>?
}

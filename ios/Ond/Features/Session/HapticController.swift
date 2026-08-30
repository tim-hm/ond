import CoreHaptics
import OndKit
import os
import UIKit

/// The phone breathing with you: one haptic pattern per phase, shaped like
/// the breath it accompanies. It lives in the app target, not `OndKit`:
/// CoreHaptics is iOS-only and the watch has a different vocabulary
/// (`WKHapticType`, discrete taps). The session engine drives both through
/// `SessionCueing` without knowing which one it has.
@MainActor
final class HapticController {
    private static let logger = Logger(category: "haptics")

    /// Whether the hardware can play a pattern at all. A Haptic Touch-only
    /// device and the simulator both answer no, and both fall back to
    /// `UIImpactFeedbackGenerator` — which cannot express a curve, so the
    /// fallback marks boundaries rather than shaping phases.
    private let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    /// How hard everything below lands. Resolved once, when the session is
    /// composed: the patterns are built from it and a change mid-session would
    /// mean two halves of one breath at two strengths.
    private let strength: HapticStrength

    private var engine: CHHapticEngine?
    private var impacts: [UIImpactFeedbackGenerator.FeedbackStyle: UIImpactFeedbackGenerator] = [:]

    /// The pattern still playing, if there is one. A breath's envelope runs
    /// for most of its phase, so something is usually in flight mid-phase: a
    /// pause left alone would play the rest of the breath out, and an arriving
    /// cue must stop the departing one rather than overlap it.
    private var playing: (any CHHapticPatternPlayer)?

    init(strength: HapticStrength) {
        self.strength = strength
    }

    func prepare() {
        guard supportsHaptics else {
            prepareFallback()
            return
        }

        do {
            let engine = try CHHapticEngine()

            // The engine is reset out from under us by an audio-session
            // interruption or a media-services restart. Without this the rest of
            // the session is silent, with nothing in the UI to say so.
            engine.resetHandler = { [weak self] in
                Task { @MainActor in self?.restart() }
            }
            engine.stoppedHandler = { reason in
                Self.logger.notice("haptic engine stopped: \(reason.rawValue)")
            }

            try engine.start()
            self.engine = engine
        } catch {
            Self.logger
                .error("haptic engine unavailable: \(error.localizedDescription, privacy: .public)")
        }
    }

    func play(_ beat: SessionTimeline.Beat) {
        guard let engine else {
            playFallback(for: beat.kind)
            return
        }

        stopPlaying()
        do {
            let player = try engine.makePlayer(with: pattern(for: beat))
            try player.start(atTime: CHHapticTimeImmediate)
            playing = player
        } catch {
            Self.logger
                .error("haptic pattern failed: \(error.localizedDescription, privacy: .public)")
            playFallback(for: beat.kind)
        }
    }

    /// Three quickening taps — a full stop that feels like one, without asking
    /// the person to look at the screen to know they are done.
    func playCompletion() {
        guard let engine else {
            impacts[.medium]?.impactOccurred(intensity: CGFloat(strength.intensity(1)))
            return
        }

        do {
            let taps = [0.0, 0.14, 0.28].enumerated().map { index, time in
                tap(
                    SessionHapticShape.Transient(
                        intensity: 0.5 + Float(index) * 0.2,
                        sharpness: 0.4
                    ),
                    at: time
                )
            }
            let player = try engine.makePlayer(with: CHHapticPattern(events: taps, parameters: []))
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            Self.logger
                .error("completion haptic failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Stops the breath in flight where it stands. The engine stays warm, as
    /// `SessionCueing.pause()` requires. `resume()` does not reinstate the
    /// pattern: picking a swell up mid-phase is the half-a-phase cue the
    /// entry-only rule in `SessionModel.runCueLoop()` refuses, so this and
    /// `WatchHapticController` both wait for the next boundary.
    func pause() {
        stopPlaying()
    }

    func stop() {
        stopPlaying()
        engine?.stop()
        engine = nil
        impacts.removeAll()
    }

    private func stopPlaying() {
        guard let playing else { return }
        self.playing = nil

        do {
            try playing.stop(atTime: CHHapticTimeImmediate)
        } catch {
            Self.logger
                .error(
                    "haptic pattern would not stop: \(error.localizedDescription, privacy: .public)"
                )
        }
    }

    /// Warms one generator per style. The first `impactOccurred` on a cold
    /// generator is the one that arrives late, and that is a phase boundary.
    private func prepareFallback() {
        for style in [UIImpactFeedbackGenerator.FeedbackStyle.medium, .soft, .rigid, .light] {
            let generator = UIImpactFeedbackGenerator(style: style)
            generator.prepare()
            impacts[style] = generator
        }
    }

    private func restart() {
        do {
            try engine?.start()
        } catch {
            Self.logger
                .error(
                    "haptic engine restart failed: \(error.localizedDescription, privacy: .public)"
                )
        }
    }

    /// Renders the shared phase shape without adding platform-specific tuning.
    /// OndKit owns the authored values so the phone's waveform is also the
    /// envelope the watch translates into its smaller haptic vocabulary.
    private func pattern(for beat: SessionTimeline.Beat) throws -> CHHapticPattern {
        let shape = SessionHapticShape(beat: beat)
        var events = [tap(shape.onset, at: 0)]
        var curves: [CHHapticParameterCurve] = []

        if let envelope = shape.envelope {
            let (event, curve) = swell(envelope)
            events.append(event)
            curves.append(curve)
        }
        if let reminder = shape.reminder {
            events += reminders(reminder, within: beat.breathing)
        }

        return try CHHapticPattern(events: events, parameterCurves: curves)
    }

    /// A continuous event whose intensity is driven across the envelope's own
    /// span by a parameter curve. The curve multiplies the event's intensity,
    /// which is why the event is authored at full strength and the shape lives
    /// entirely in the control points.
    private func swell(
        _ envelope: SessionHapticShape.Envelope
    ) -> (CHHapticEvent, CHHapticParameterCurve) {
        let start = envelope.span.lowerBound.seconds
        let seconds = envelope.span.upperBound.seconds - start
        let event = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                CHHapticEventParameter(
                    parameterID: .hapticSharpness,
                    value: strength.sharpness(envelope.sharpness)
                ),
            ],
            relativeTime: start,
            duration: seconds
        )

        // The curve, not the event, is where the strength lands: the event is
        // authored at full intensity precisely so the shape lives in these
        // control points, and scaling the event instead would flatten the swell
        // rather than raise it. Control points are relative to the curve's own
        // start, so they run from zero while the curve begins at the envelope.
        let curve = CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: [
                CHHapticParameterCurve.ControlPoint(
                    relativeTime: 0,
                    value: strength.intensity(envelope.startIntensity)
                ),
                CHHapticParameterCurve.ControlPoint(
                    relativeTime: seconds,
                    value: strength.intensity(envelope.endIntensity)
                ),
            ],
            relativeTime: start
        )

        return (event, curve)
    }

    /// The marks that say a long hold is still running, as far as the length
    /// the hold aims for. A retention ends on the person's own tap, so nothing
    /// is scheduled past the aim.
    private func reminders(
        _ reminder: SessionHapticShape.Reminder,
        within span: Duration
    ) -> [CHHapticEvent] {
        let step = reminder.interval.seconds
        guard step > 0 else { return [] }
        return stride(from: step, to: span.seconds, by: step).map { tap(reminder.tap, at: $0) }
    }

    private func tap(
        _ transient: SessionHapticShape.Transient,
        at time: TimeInterval
    ) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(
                    parameterID: .hapticIntensity,
                    value: strength.intensity(transient.intensity)
                ),
                CHHapticEventParameter(
                    parameterID: .hapticSharpness,
                    value: strength.sharpness(transient.sharpness)
                ),
            ],
            relativeTime: time
        )
    }

    /// The four styles carry as much of the distinction as this API can: the
    /// breaths differ from each other, and both holds differ from both breaths.
    private func playFallback(for kind: PhaseKind) {
        let style: UIImpactFeedbackGenerator.FeedbackStyle = switch kind {
        case .inhale: .medium
        case .exhale: .soft
        case .holdIn: .rigid
        case .holdOut: .light
        }

        guard let generator = impacts[style] else { return }
        // The one strength knob this API has. A device without CoreHaptics still
        // deserves the setting to mean something.
        generator.impactOccurred(intensity: CGFloat(strength.intensity(1)))
        // Re-armed straight away: the next boundary is seconds away, and a cold
        // generator is the one that arrives late.
        generator.prepare()
    }
}

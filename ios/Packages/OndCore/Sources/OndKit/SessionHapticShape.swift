import Foundation

/// The authored tactile shape of one session phase, before a device renders
/// it. Three elements and no more: a mark on the boundary, an envelope
/// through the phase, and silence. The phone plays these values through Core
/// Haptics. The watch varies neither amplitude nor sharpness, so it renders
/// the envelope as pulse density and the onset as its nearest system cue.
public struct SessionHapticShape: Sendable, Equatable {
    /// A momentary event: how hard the tap lands, and its tactile edge.
    public struct Transient: Sendable, Equatable {
        public let intensity: Float
        public let sharpness: Float

        public init(intensity: Float, sharpness: Float) {
            self.intensity = intensity
            self.sharpness = sharpness
        }
    }

    /// A continuous event whose intensity travels from `startIntensity` as the
    /// movement begins to `endIntensity` as it ends, at a fixed tactile edge.
    public struct Envelope: Sendable, Equatable {
        public let startIntensity: Float
        public let endIntensity: Float
        public let sharpness: Float
        /// When it moves, measured from the phase boundary: after the onset's
        /// room, and stopping before the silence that closes the phase. Decided
        /// once, here, so the two renderers cannot each derive their own.
        public let span: Range<Duration>
    }

    /// A tap repeated while the phase runs, saying it is still running.
    public struct Reminder: Sendable, Equatable {
        public let tap: Transient
        public let interval: Duration
    }

    /// The mark on the phase boundary, played before anything else.
    public let onset: Transient
    /// The movement through the phase, or nil where there is none — both
    /// holds, `drum`, and any phase too short to carry a mark and a movement
    /// both. A phase that short keeps the mark.
    public let envelope: Envelope?
    /// What says a long hold is still running, or nil, which is every phase
    /// but a retention.
    public let reminder: Reminder?

    /// Resolves the device-independent shape for a laid-out session beat.
    /// A breath's envelope endpoints come from its actual lung fullness, not
    /// from its direction alone — which is what lets a stacked inhale such as
    /// the sigh's sip start almost full and add only the final tenth.
    public init(beat: SessionTimeline.Beat) {
        let pattern = beat.hapticPattern
        onset = Self.onset(of: beat, in: pattern)
        envelope = Self.envelope(of: beat, in: pattern)
        reminder = pattern == .longHold ? Self.holdReminder : nil
    }

    /// The mark each phase opens with. Direction is carried by sharpness, not
    /// strength: two taps of equal strength and different sharpness are told
    /// apart in the dark, two of equal sharpness are not. Every inhale mark is
    /// sharper than every exhale mark, and `HapticStrength` shifts sharpness
    /// by the same amount for all of them, so no setting can invert the order.
    private static func onset(
        of beat: SessionTimeline.Beat,
        in pattern: HapticPattern
    ) -> Transient {
        switch beat.kind {
        case .inhale:
            beat.stacksOnPrevious || pattern == .sip ? stackedInhaleOnset : inhaleOnset
        case .exhale:
            pattern == .press ? pressedExhaleOnset : exhaleOnset
        case .holdIn:
            holdInOnset
        case .holdOut:
            holdOutOnset
        }
    }

    /// The movement through the phase. It opens after the onset rather than
    /// carrying the boundary itself, which is what makes its quiet start
    /// correct. Both holds are silent once their mark has landed.
    private static func envelope(
        of beat: SessionTimeline.Beat,
        in pattern: HapticPattern
    ) -> Envelope? {
        guard pattern != .drum, let span = span(of: beat) else { return nil }

        switch beat.kind {
        case .inhale:
            return Envelope(
                startIntensity: inhaleIntensity(at: beat.startFullness),
                endIntensity: inhaleIntensity(at: beat.endFullness),
                sharpness: 0.3,
                span: span
            )
        case .exhale:
            let pressed = pattern == .press
            return Envelope(
                startIntensity: pressed ? pressedExhaleLevel
                    : exhaleIntensity(at: beat.startFullness),
                endIntensity: pressed ? pressedExhaleLevel
                    : exhaleIntensity(at: beat.endFullness),
                sharpness: 0.1,
                span: span
            )
        case .holdIn, .holdOut:
            return nil
        }
    }

    private static func span(of beat: SessionTimeline.Beat) -> Range<Duration>? {
        let end = beat.breathing - tail
        guard onsetLead < end else { return nil }
        return onsetLead ..< end
    }

    /// Room for the onset to land and be felt before the envelope opens.
    private static let onsetLead: Duration = .milliseconds(300)

    /// Quiet before the next phase boundary. A mark that arrives after a beat
    /// of nothing reads as a boundary; one that arrives inside continuous
    /// texture reads as texture.
    private static let tail: Duration = .milliseconds(300)

    /// Begin, and go up.
    private static let inhaleOnset = Transient(intensity: 0.55, sharpness: 0.65)
    /// More, on top of that — the sigh's sip.
    private static let stackedInhaleOnset = Transient(intensity: 0.4, sharpness: 0.75)
    /// Let go.
    private static let exhaleOnset = Transient(intensity: 0.45, sharpness: 0.25)
    /// A breath out that is worked against, so the mark that starts it is firmer.
    private static let pressedExhaleOnset = Transient(intensity: 0.6, sharpness: 0.35)

    /// The firmest mark in the session, set against the softest below it. A
    /// hold at the top is something you are doing; a hold at the bottom is
    /// something you are not. `HapticStrength.intensity` floors at 0.05, and
    /// hold-out is the phase that floor exists for.
    private static let holdInOnset = Transient(intensity: 0.9, sharpness: 0.8)
    private static let holdOutOnset = Transient(intensity: 0.45, sharpness: 0.1)

    /// What a resisted exhale holds at rather than decaying to. The effort is
    /// constant, so the cue is too.
    private static let pressedExhaleLevel: Float = 0.5

    /// One mark every quarter minute, saying the retention is still running.
    private static let holdReminder = Reminder(
        tap: Transient(intensity: 0.35, sharpness: 0.6),
        interval: .seconds(15)
    )

    private static func inhaleIntensity(at fullness: Double) -> Float {
        authoredIntensity(at: fullness, empty: 0.12, full: 0.85)
    }

    private static func exhaleIntensity(at fullness: Double) -> Float {
        authoredIntensity(at: fullness, empty: 0.08, full: 0.8)
    }

    private static func authoredIntensity(at fullness: Double, empty: Float, full: Float) -> Float {
        let level = SessionTimeline.Beat.level(ofFullness: fullness)
        return empty + (full - empty) * Float(level)
    }
}

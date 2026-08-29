import OndKit
import SwiftUI

extension View {
    /// Makes the receiver the session's one spoken element: the phase, and
    /// how long is left in it. Whichever of the two carries the phase wears
    /// this — words under full guidance, the orb under Just the visuals — so
    /// both levels read the same. Written out rather than combined from the
    /// labels: the seconds are still owed on a rhythm that does not print them.
    func speaksPhase(_ beat: SessionTimeline.Beat?, at elapsed: Duration) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenPhase(of: beat))
            .accessibilityValue(secondsRemaining(in: beat, at: elapsed))
    }
}

/// The cue and whatever the line under it adds, joined as the lock screen
/// joins them — see `SessionCueLabel`. Without this the ear hears less than
/// the eye reads: humming breath's whole mechanic is a manner, so VoiceOver
/// would say breathe out and never say hum. `BreathHint.spokenAddition`
/// decides which rungs the spoken sentence does not already hold.
private func spokenPhase(of beat: SessionTimeline.Beat?) -> String {
    guard let beat else { return "" }
    guard let addition = beat.hint.spokenAddition else { return beat.spokenInstruction }
    return "\(beat.spokenInstruction), \(addition)"
}

/// Whole seconds left in the phase, counting down and never showing zero — the
/// last second of a phase is still a second of it. Empty where there is no beat,
/// which is the one thing the screen's own count does not have to answer for.
private func secondsRemaining(in beat: SessionTimeline.Beat?, at elapsed: Duration) -> String {
    guard let beat else { return "" }
    return "\(beat.secondsRemaining(at: elapsed))"
}

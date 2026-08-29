import OndKit
import SwiftUI

extension View {
    /// Makes the receiver the session's spoken element: the phase, and how
    /// long is left in it. The guide wears it and stays hidden while the words
    /// speak, so both guidance levels read the same. Written out rather than
    /// combined from the labels: the seconds are still owed on a rhythm that
    /// does not print them.
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
func spokenPhase(of beat: SessionTimeline.Beat?) -> String {
    guard let beat else { return "" }
    guard let addition = beat.hint.spokenAddition else { return beat.spokenInstruction }
    return "\(beat.spokenInstruction), \(addition)"
}

/// Whole seconds left in the phase, counting down and never showing zero — the
/// last second of a phase is still a second of it. The Count slot prints this
/// same string, so the eye and the ear cannot name different seconds. Empty
/// where there is no beat.
func secondsRemaining(in beat: SessionTimeline.Beat?, at elapsed: Duration) -> String {
    guard let beat else { return "" }
    return "\(beat.secondsRemaining(at: elapsed))"
}

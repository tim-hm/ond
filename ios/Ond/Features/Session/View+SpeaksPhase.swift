import OndKit
import SwiftUI

extension View {
    /// Makes the receiver the session's one spoken element: the phase, and how
    /// long is left in it.
    ///
    /// Whichever of the two carries the phase wears this — the words under full
    /// guidance, the orb under Just the visuals — so the same screen is read the
    /// same way at either level, and the two cannot drift apart.
    ///
    /// Written out rather than combined from the labels on screen, because the
    /// seconds are still owed on a fast rhythm that does not print them: the
    /// wrist's rule, which took the digits off the screen and left them in
    /// VoiceOver.
    func speaksPhase(_ beat: SessionTimeline.Beat?, at elapsed: Duration) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel(beat?.spokenInstruction ?? "")
            .accessibilityValue(secondsRemaining(in: beat, at: elapsed))
    }
}

/// Whole seconds left in the phase, counting down and never showing zero — the
/// last second of a phase is still a second of it. Empty where there is no beat,
/// which is the one thing the screen's own count does not have to answer for.
private func secondsRemaining(in beat: SessionTimeline.Beat?, at elapsed: Duration) -> String {
    guard let beat else { return "" }
    return "\(beat.secondsRemaining(at: elapsed))"
}

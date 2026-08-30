import Foundation

/// How far through the person is. Every answer here is a pure function of the
/// timeline and the beat the cue loop last entered, so reading one changes
/// nothing and a view may take it every frame.
public extension SessionModel {
    /// How long the plan has left — the session headers' "left" number, kept
    /// here so hand and wrist subtract the same clock. Meaningless where the
    /// plan waits on the person: gate on `Technique.hasOpenEndedStage` first.
    var remaining: Duration {
        timeline.totalDuration - elapsed
    }

    /// The beat the screen describes: before the cue loop's first turn, and
    /// after the plan runs out, `currentBeat` is nil and the timeline answers.
    /// Every word on the session screen reads off this rather than sampling
    /// the clock, which can be a whole phase late in bellows breathing. Public
    /// for the player, which would otherwise re-derive it without the fallback.
    var describingBeat: SessionTimeline.Beat? {
        currentBeat ?? timeline.beat(at: elapsed)
    }
}

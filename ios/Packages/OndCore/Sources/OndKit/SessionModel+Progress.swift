import Foundation

/// How far through the person is: the round, and the cycle of the stage on
/// screen.
///
/// Apart from the model's own file because none of it is the session *running*.
/// Every answer here is a pure function of the timeline and the beat the cue
/// loop last entered, so reading one changes nothing and a view may take it
/// every frame.
public extension SessionModel {
    /// How long the plan has left — the session headers' "left" number, kept
    /// here so hand and wrist subtract the same clock. Meaningless where the
    /// plan waits on the person: gate on `Technique.hasOpenEndedStage` first.
    var remaining: Duration {
        timeline.totalDuration - elapsed
    }

    /// Which round the person is in, counting from one.
    var currentRound: Int {
        describingBeat.map { $0.round + 1 } ?? timeline.rounds
    }

    /// Which cycle of the current stage the person is in, counting from one.
    ///
    /// Belongs here rather than in the view: "no current beat means the last
    /// cycle" is what a run-out timeline means, and the summary and the watch
    /// app will need the same answer.
    var currentCycle: Int {
        describingBeat.map { $0.cycle + 1 } ?? cyclesInCurrentStage
    }

    /// How many cycles the stage on screen plays — the "of 30" in the header.
    var cyclesInCurrentStage: Int {
        let stages = technique.stages
        guard let stage = describingBeat?.stage, stages.indices.contains(stage) else {
            return stages.last?.cycles ?? 1
        }
        return stages[stage].cycles
    }

    /// The beat the screen describes. Before the cue loop's first turn, and
    /// after the plan runs out, `currentBeat` is nil and the timeline answers.
    ///
    /// What every word on the session screen is read off, rather than each place
    /// sampling the clock itself: the cue loop enters a beat exactly on its
    /// boundary, where a once-a-second sample can be a whole phase late — most of
    /// one, in bellows breathing. Public for the player, which draws the phase
    /// this describes and would otherwise re-derive it without the fallback.
    var describingBeat: SessionTimeline.Beat? {
        currentBeat ?? timeline.beat(at: elapsed)
    }
}

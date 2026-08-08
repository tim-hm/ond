import Foundation

/// How far through the person is: the progress bar's value, the round, and the
/// cycle of the stage on screen.
///
/// Apart from the model's own file because none of it is the session *running*.
/// Every answer here is a pure function of the timeline and the beat the cue
/// loop last entered, so reading one changes nothing and a view may take it
/// every frame.
public extension SessionModel {
    /// How far through the whole session, as 0...1 — the progress bar's value.
    ///
    /// Takes the elapsed time rather than reading it, so a view already holding
    /// the value it drew this frame with does not take a second, slightly later
    /// reading off the clock to draw the bar.
    func progress(at elapsed: Duration) -> Double {
        let total = timeline.totalDuration.milliseconds
        guard total > 0 else { return 1 }
        return Double(elapsed.milliseconds) / Double(total)
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

    /// The beat the header describes. Before the cue loop's first turn, and
    /// after the plan runs out, `currentBeat` is nil and the timeline answers.
    private var describingBeat: SessionTimeline.Beat? {
        currentBeat ?? timeline.beat(at: elapsed)
    }
}

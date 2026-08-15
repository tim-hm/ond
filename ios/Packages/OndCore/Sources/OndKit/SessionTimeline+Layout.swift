import Foundation

extension SessionTimeline {
    struct Layout {
        let beats: [Beat]
        let rounds: Int
        let cycleEnds: [Duration]
        let totalDuration: Duration
        let hintsAnyBeat: Bool

        init(stages: [Stage], rounds: Int, register: CopyRegister) {
            let rounds = max(rounds, 1)
            var beats: [Beat] = []
            var cycleEnds: [Duration] = []
            var start = Duration.zero
            var level = Self.openingLevel(of: stages)

            for round in 0 ..< rounds {
                for (stageIndex, stage) in stages.enumerated() {
                    // Two thresholds, deliberately: one asks whether a phase
                    // outruns its own count, the other whether the cycle outruns
                    // a resting rate. Both are read off the stage, and the sigh
                    // is the entry that separates them.
                    let (isFastRhythm, breathesFast) = (stage.isFastRhythm, stage.breathesFast)
                    let cueRoles = stage.cueRoles
                    for cycle in 0 ..< max(stage.cycles, 1) {
                        let levels = BreathRhythm.levels(through: stage.phases, from: level)
                        for (phaseIndex, phase) in stage.phases.enumerated() {
                            let startLevel = phaseIndex == 0 ? level : levels[phaseIndex - 1]
                            let duration = Self.duration(of: phase, in: stage, round: round)
                            let stacksOnPrevious = Self.prepareTurnGap(in: &beats, before: phase)
                            beats.append(
                                Beat(
                                    id: beats.count,
                                    breath: phase.breath,
                                    round: round,
                                    stage: stageIndex,
                                    opensStage: !beats.isEmpty && cycle == 0 && phaseIndex == 0,
                                    stacksOnPrevious: stacksOnPrevious,
                                    cueRole: cueRoles[phaseIndex],
                                    cycle: cycle,
                                    phase: phaseIndex,
                                    isOpenEnded: stage.openEnded,
                                    isFastRhythm: isFastRhythm,
                                    breathesFast: breathesFast,
                                    manner: phase.manner,
                                    register: register,
                                    start: start,
                                    duration: duration,
                                    turnGap: Self.turnGap(ofPhase: duration, in: stage),
                                    startFullness: Beat.fullness(of: startLevel),
                                    endFullness: Beat.fullness(of: levels[phaseIndex])
                                )
                            )
                            start += duration
                        }
                        level = levels.last ?? level
                        cycleEnds.append(start)
                    }
                }
            }

            self.beats = beats
            self.rounds = rounds
            self.cycleEnds = cycleEnds
            totalDuration = start
            hintsAnyBeat = beats.contains { $0.hint.line != nil }
        }

        /// The stillness at the end of a phase, and none at all on a stage the
        /// person ends: a retention has no next boundary for a gap to borrow
        /// from, because nothing but their own tap decides where it is.
        private static func turnGap(ofPhase duration: Duration, in stage: Stage) -> Duration {
            stage.openEnded ? .zero : SessionTurnGap.length(ofPhase: duration)
        }

        private static func prepareTurnGap(in beats: inout [Beat], before phase: Phase) -> Bool {
            let stacksOnPrevious = beats.last?.breath.kind == phase.breath.kind
                && !phase.breath.kind.isHold
            guard stacksOnPrevious,
                  let previous = beats.indices.last,
                  !beats[previous].isOpenEnded
            else { return stacksOnPrevious }

            beats[previous].turnGap = SessionTurnGap.length(
                ofPhase: beats[previous].duration,
                beforeStackedBreath: true
            )
            return stacksOnPrevious
        }

        private static func duration(of phase: Phase, in stage: Stage, round: Int) -> Duration {
            stage.openEnded ? phase.duration * (round + 1) : phase.duration
        }

        private static func openingLevel(of stages: [Stage]) -> Double {
            switch stages.first?.phases.first?.kind {
            case .exhale, .holdIn: 1
            case .inhale, .holdOut, nil: 0
            }
        }
    }
}

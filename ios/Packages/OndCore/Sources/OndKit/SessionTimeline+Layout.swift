import Foundation

extension SessionTimeline {
    /// What laying out one stage carries into the next: the beats so far, the
    /// clock, how full the lungs are, and the gap the phase that just went
    /// past authored. One value rather than five `inout` parameters, because
    /// they are only ever read and written together.
    private struct Cursor {
        var beats: [Beat] = []
        var cycleEnds: [Duration] = []
        var start = Duration.zero
        var level: Double
        var previousTurnGap: Duration?
    }

    struct Layout {
        let beats: [Beat]
        let rounds: Int
        let cycleEnds: [Duration]
        let totalDuration: Duration
        let hintsAnyBeat: Bool

        init(stages: [Stage], rounds: Int, register: CopyRegister) {
            let rounds = max(rounds, 1)
            var cursor = Cursor(level: Self.openingLevel(of: stages))

            for round in 0 ..< rounds {
                for (stageIndex, stage) in stages.enumerated() {
                    Self.layOut(
                        stage,
                        at: stageIndex,
                        round: round,
                        register: register,
                        into: &cursor
                    )
                }
            }

            beats = cursor.beats
            self.rounds = rounds
            cycleEnds = cursor.cycleEnds
            totalDuration = cursor.start
            hintsAnyBeat = cursor.beats.contains { $0.hint.line != nil }
        }

        /// Appends one stage's cycles to the plan, in play order.
        private static func layOut(
            _ stage: Stage,
            at stageIndex: Int,
            round: Int,
            register: CopyRegister,
            into cursor: inout Cursor
        ) {
            // Two thresholds, deliberately: one asks whether a phase outruns
            // its own count, the other whether the cycle outruns a resting
            // rate. Both are read off the stage, and the sigh is the entry
            // that separates them.
            let (isFastRhythm, breathesFast) = (stage.isFastRhythm, stage.breathesFast)
            let cueRoles = stage.cueRoles
            let hapticPatterns = stage.phases.map { HapticPattern.resolved($0.hapticPattern) }

            for cycle in 0 ..< max(stage.cycles, 1) {
                let levels = BreathRhythm.levels(through: stage.phases, from: cursor.level)
                for (phaseIndex, phase) in stage.phases.enumerated() {
                    let startLevel = phaseIndex == 0 ? cursor.level : levels[phaseIndex - 1]
                    let duration = Self.duration(of: phase, in: stage, round: round)
                    let stacksOnPrevious = prepareTurnGap(in: &cursor, before: phase)
                    cursor.beats.append(
                        Beat(
                            id: cursor.beats.count,
                            breath: phase.breath,
                            round: round,
                            stage: stageIndex,
                            opensStage: !cursor.beats.isEmpty && cycle == 0 && phaseIndex == 0,
                            stacksOnPrevious: stacksOnPrevious,
                            cueRole: cueRoles[phaseIndex],
                            cycle: cycle,
                            phase: phaseIndex,
                            isOpenEnded: stage.openEnded,
                            isFastRhythm: isFastRhythm,
                            breathesFast: breathesFast,
                            manner: phase.manner,
                            voiceScript: phase.voiceScript,
                            hapticPattern: hapticPatterns[phaseIndex],
                            register: register,
                            start: cursor.start,
                            duration: duration,
                            turnGap: turnGap(of: phase, playing: duration, in: stage),
                            startFullness: Beat.fullness(of: startLevel),
                            endFullness: Beat.fullness(of: levels[phaseIndex])
                        )
                    )
                    cursor.previousTurnGap = phase.turnGap
                    cursor.start += duration
                }
                cursor.level = levels.last ?? cursor.level
                cursor.cycleEnds.append(cursor.start)
            }
        }

        /// The stillness at the end of a phase, and none at all on a stage the
        /// person ends: a retention has no next boundary for a gap to borrow
        /// from, because nothing but their own tap decides where it is.
        /// `playing` is the length this round breathes it at, which an
        /// open-ended stage lengthens each round.
        private static func turnGap(
            of phase: Phase,
            playing duration: Duration,
            in stage: Stage
        ) -> Duration {
            stage.openEnded
                ? .zero
                : SessionTurnGap.length(ofPhase: duration, authored: phase.turnGap)
        }

        /// Widens the previous beat's gap where this phase stacks on it. The
        /// authored gap goes back in with it, so a table that already says how
        /// this turn goes still wins — `SessionTurnGap.length` keeps that rule
        /// rather than this guard keeping a second copy of it.
        private static func prepareTurnGap(in cursor: inout Cursor, before phase: Phase) -> Bool {
            guard let previous = cursor.beats.indices.last else { return false }
            let stacksOnPrevious = cursor.beats[previous].breath.kind == phase.breath.kind
                && !phase.breath.kind.isHold
            guard stacksOnPrevious, !cursor.beats[previous].isOpenEnded
            else { return stacksOnPrevious }

            cursor.beats[previous].turnGap = SessionTurnGap.length(
                ofPhase: cursor.beats[previous].duration,
                authored: cursor.previousTurnGap,
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

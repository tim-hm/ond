import Foundation

/// When a discreet session touches the wrist: short guided bursts,
/// `cyclesPerBurst` cycles each, with nothing at all between. The gaps grow
/// ~1.6× (3, 5, 8, 13 minutes) — the physiology does its work up front, and a
/// fixed interval habituates into furniture. Open-loop on purpose (a
/// responsive curve fails in the wrong shape), and constants, cheap to change.
public enum DiscreetCadence {
    /// The silences between bursts, in play order.
    public static let gaps: [Duration] = [
        .seconds(3 * 60),
        .seconds(5 * 60),
        .seconds(8 * 60),
        .seconds(13 * 60),
    ]

    /// How many cycles of the technique's pattern one burst is worth. Six,
    /// which for the evenly paced techniques this mode is for is about a
    /// minute: long enough to entrain to, short enough to ride out without
    /// leaving the conversation you are sitting in.
    public static let cyclesPerBurst = 6

    /// Where each burst begins, measured from the start of the session.
    ///
    /// One longer than `gaps`, because the first burst opens the session and
    /// every gap is followed by another. Derived rather than written down, so
    /// the curve cannot come to disagree with itself.
    public static let burstStarts: [Duration] = gaps.reduce(into: [.zero]) { starts, gap in
        starts.append((starts.last ?? .zero) + gap)
    }

    /// One burst of `technique`, laid out from t = 0 like any other session.
    /// The first stage's pattern only: the techniques this mode is meant for
    /// have no second stage, and later stages should not arrive unannounced in
    /// a meeting. A technique with no stages yields an empty burst rather than
    /// trapping — a session is not worth a crash.
    public static func burst(of technique: Technique) -> SessionTimeline {
        guard let stage = technique.stages.first else {
            return SessionTimeline(stages: [], rounds: 1)
        }

        return SessionTimeline(
            stages: [Stage(phases: stage.phases, cycles: cyclesPerBurst)],
            rounds: 1
        )
    }

    /// How long a discreet session over `technique` lasts: every gap, plus the
    /// closing burst that outlives the last of them.
    ///
    /// - Parameter technique: the technique being delivered discreetly.
    public static func duration(of technique: Technique) -> Duration {
        gaps.reduce(.zero, +) + burst(of: technique).totalDuration
    }

    /// Cycles and breaths wholly behind `elapsed`, folded across the bursts.
    /// The gaps contribute nothing, which is the point: minutes of silence are
    /// the delivery mode, not practice to count. Here beside `burstStarts` and
    /// `duration(of:)` because it is the fourth reading of the same curve — a
    /// cadence reshaped in one place must not leave its arithmetic in another.
    public static func progress(
        of technique: Technique,
        at elapsed: Duration
    ) -> (cycles: Int, breaths: Int) {
        let burst = burst(of: technique)
        var cycles = 0
        var breaths = 0
        for burstStart in burstStarts where elapsed > burstStart {
            let within = min(elapsed - burstStart, burst.totalDuration)
            cycles += burst.cyclesCompleted(at: within)
            breaths += burst.breathsCompleted(at: within)
        }
        return (cycles, breaths)
    }
}

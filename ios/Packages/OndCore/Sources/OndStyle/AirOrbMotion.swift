import OndKit

public struct AirOrbMotion: Sendable {
    public struct Frame: Sendable, Equatable {
        public let scale: Double
        public let swirl: Double
    }

    private let timeline: SessionTimeline
    private let movingStarts: [Double]

    public init(timeline: SessionTimeline) {
        self.timeline = timeline
        var moving = 0.0
        movingStarts = timeline.beats.map { beat in
            let start = moving
            if !beat.kind.isHold {
                moving += beat.breathing / .seconds(1)
            }
            return start
        }
    }

    public func frame(at elapsed: Duration, stationary: Bool = false) -> Frame {
        guard !stationary, let beat = timeline.beat(at: elapsed) else {
            return Frame(scale: 0.84, swirl: 0)
        }
        let fraction = beat.fraction(at: elapsed)
        let eased = fraction * fraction * (3 - 2 * fraction)
        let travel = beat.kind.isHold ? 0 : eased * (beat.breathing / .seconds(1))
        // Exclude holds and turn gaps so motion resumes from the frozen frame.
        let moving = movingStarts[beat.id] + travel
        return Frame(
            scale: Self.scale(forFullness: beat.lungFullness(at: elapsed)),
            swirl: moving * 0.18
        )
    }

    public static func scale(forFullness fullness: Double) -> Double {
        0.62 + 0.38 * SessionTimeline.Beat.level(ofFullness: fullness)
    }
}

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

    public func frame(
        at elapsed: Duration,
        realElapsed: Duration? = nil,
        stationary: Bool = false
    ) -> Frame {
        guard !stationary, let beat = timeline.beat(at: elapsed) else {
            return Frame(scale: 0.84, swirl: 0)
        }
        let fraction = beat.fraction(at: elapsed)
        let eased = fraction * fraction * (3 - 2 * fraction)
        let travel = beat.kind.isHold ? 0 : eased * (beat.breathing / .seconds(1))
        let moving = movingStarts[beat.id] + travel
        // Real time advances during open holds and freezes when the session pauses.
        let drift = (realElapsed ?? elapsed) / .seconds(1) * 0.012
        return Frame(
            scale: Self.scale(forFullness: beat.lungFullness(at: elapsed)),
            swirl: moving * 0.18 + drift
        )
    }

    public static func scale(forFullness fullness: Double) -> Double {
        scale(forLevel: SessionTimeline.Beat.level(ofFullness: fullness))
    }

    public static func scale(forLevel level: Double) -> Double {
        0.24 + 0.76 * min(max(level, 0), 1)
    }
}

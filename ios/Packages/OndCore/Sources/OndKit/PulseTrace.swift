import CoreGraphics
import Foundation

/// One reading, and how far into the sharing it arrived.
///
/// Elapsed rather than a wall-clock date, on `SessionClock`'s reasoning: this is
/// a duration into a session, and a session's own time is not something a
/// time-zone change may edit.
public struct PulseReading: Sendable, Equatable {
    public let elapsed: Duration
    public let beatsPerMinute: Int

    public init(elapsed: Duration, beatsPerMinute: Int) {
        self.elapsed = elapsed
        self.beatsPerMinute = beatsPerMinute
    }
}

/// Every reading one session's wrist sent, and what can honestly be drawn from
/// them. Held for the length of a session and thrown away with the screen —
/// `PulseMonitor` owns the only one. Nothing persists it, nothing syncs it, and
/// it is deliberately not on `SessionRecord`: a heart rate is health data, and
/// the journal that reaches the server is not where it goes.
public struct PulseTrace: Sendable, Equatable {
    /// How many readings before there is a line rather than a guess. Two drawn
    /// as a curve is a straight line that looks like a finding and is not one;
    /// five is the fewest with a shape of its own — at `PulseRelay.spacing`, a
    /// little over half a minute of sharing.
    static let minimumReadings = 5

    public private(set) var readings: [PulseReading] = []

    /// How long the session ran, measured from the first reading — the width
    /// the drawing spans. Nil until the session ends. Without it [`runs()`]
    /// falls back to the last reading, which is wrong for a wrist that stopped
    /// sharing early: ninety seconds stretched across a fifteen-minute chart
    /// reads as a heart that settled over the whole practice.
    public private(set) var span: Duration?

    public init() {}

    /// Internal, like [`append(_:)`] and for its reason: the only thing that may
    /// say what somebody's heart did is the model taking the readings off the
    /// radio. A public one would be the same authority by another door.
    init(readings: [PulseReading]) {
        self.readings = readings
    }

    /// The slowest and fastest the heart got while sharing, or nil for a trace
    /// with nothing in it. The labels the drawing hangs its scale on, and the
    /// only two numbers it states.
    public var range: ClosedRange<Int>? {
        // Lazily, so neither end materialises an array of every rate just to
        // reduce it away again.
        let rates = readings.lazy.map(\.beatsPerMinute)
        guard let lowest = rates.min(), let highest = rates.max() else { return nil }
        return lowest ... highest
    }

    /// Whether there is enough here to be worth a drawing. A short session, a
    /// wrist that woke late, a watch nobody was wearing: all answer false, and
    /// the surface shows nothing — silence is this feature's designed failure
    /// mode, and nothing here ever explains why there is no line.
    public var isWorthDrawing: Bool {
        readings.count >= Self.minimumReadings
    }

    /// The readings as one or more runs of a shape, the first at x = 0 and the
    /// end of the session at x = 1, with the slowest reading at y = 0 and the
    /// fastest at y = 1. The six geometry decisions are in
    /// `docs/architecture.md` under "Pulse trace geometry".
    public func runs() -> [[CGPoint]] {
        guard let range, let last = readings.last else { return [] }

        let span = span ?? last.elapsed
        let spread = range.upperBound - range.lowerBound

        var runs: [[CGPoint]] = []
        var run: [CGPoint] = []
        var previous: Duration?

        for reading in readings {
            if let previous, reading.elapsed - previous > PulseMonitor.staleness {
                runs.append(run)
                run = []
            }
            previous = reading.elapsed

            run.append(
                CGPoint(
                    x: span > .zero ? reading.elapsed / span : 0,
                    y: spread > 0
                        ? Double(reading.beatsPerMinute - range.lowerBound) / Double(spread)
                        : 0.5
                )
            )
        }
        runs.append(run)

        // A run of one reading is a dot the stroke cannot draw and a reader
        // cannot place. Dropped rather than drawn, which is the same silence
        // this feature keeps everywhere else.
        return runs.filter { $0.count > 1 }
    }

    /// Adds a reading. Internal: the only thing that may say what somebody's
    /// heart did is the model taking the readings off the radio.
    mutating func append(_ reading: PulseReading) {
        readings.append(reading)
    }

    /// States how long the session ran, once it has — see [`span`]. Internal
    /// for [`append(_:)`]'s reason.
    mutating func close(at span: Duration) {
        self.span = span
    }
}

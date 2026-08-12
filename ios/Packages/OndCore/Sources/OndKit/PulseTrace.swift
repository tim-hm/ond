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

/// A point on a drawn trace, both axes running 0...1 from the bottom left.
///
/// Unitless so the drawing decides its own size, and `Double` rather than
/// `CGPoint` so this file needs no drawing framework — `OndKit` is the domain,
/// and the one place a heart rate becomes a shape should not be the place a
/// graphics type first reaches it.
public struct PulsePoint: Sendable, Equatable {
    public let x: Double
    public let y: Double
}

/// Every reading one session's wrist sent, and what can honestly be drawn from
/// them.
///
/// Held for the length of a session and thrown away with the screen — see
/// `PulseMonitor`, which owns the only one of these. Nothing persists it,
/// nothing syncs it, and it is deliberately not on `SessionRecord`: a heart rate
/// is health data, and the journal that reaches the server is not where it goes.
///
/// The point of keeping it at all is the one thing a badge cannot show. A number
/// that reads 71 tells somebody nothing about whether the last five minutes did
/// anything; the same five minutes as a line does, and it is their own sensor
/// saying it rather than a score this app invented.
public struct PulseTrace: Sendable, Equatable {
    /// How many readings before there is a line rather than a guess.
    ///
    /// The wrist sends about every four seconds, so five is roughly the first
    /// twenty seconds of a session. Two readings drawn as a curve is a straight
    /// line between two numbers, which looks like a finding and is not one.
    static let minimumReadings = 5

    public private(set) var readings: [PulseReading] = []

    public init() {}

    public init(readings: [PulseReading]) {
        self.readings = readings
    }

    /// The slowest and fastest the heart got while sharing, or nil for a trace
    /// with nothing in it. The labels the drawing hangs its scale on, and the
    /// only two numbers it states.
    public var range: ClosedRange<Int>? {
        guard let lowest = readings.map(\.beatsPerMinute).min(),
              let highest = readings.map(\.beatsPerMinute).max()
        else {
            return nil
        }
        return lowest ... highest
    }

    /// Whether there is enough here to be worth a drawing.
    ///
    /// A short session, a wrist that woke late, a watch nobody was wearing: all
    /// of them answer false, and the surface simply shows nothing. Silence is
    /// this whole feature's designed failure mode and this is one more place it
    /// holds — nothing here ever explains why there is no line.
    public var isWorthDrawing: Bool {
        readings.count >= Self.minimumReadings
    }

    /// The readings as a shape, oldest at x = 0 and newest at x = 1, with the
    /// slowest reading at y = 0 and the fastest at y = 1.
    ///
    /// Both axes are normalised to what this session actually did, deliberately.
    /// A fixed axis — nought to two hundred — draws every settling as the same
    /// flat line, and the whole reason to show this is that the shape is legible.
    /// The cost is that the drawing says nothing about magnitude on its own,
    /// which is what [`range`] is for beside it.
    ///
    /// A heart that held one rate the whole way through has no spread to divide
    /// by and comes back level, down the middle. That is the honest drawing of
    /// it: it neither fell nor rose.
    public func points() -> [PulsePoint] {
        guard let range, let last = readings.last else { return [] }

        let span = last.elapsed
        let spread = range.upperBound - range.lowerBound

        return readings.map { reading in
            PulsePoint(
                x: span > .zero ? reading.elapsed / span : 0,
                y: spread > 0
                    ? Double(reading.beatsPerMinute - range.lowerBound) / Double(spread)
                    : 0.5
            )
        }
    }

    /// Adds a reading. Internal: the only thing that may say what somebody's
    /// heart did is the model taking the readings off the radio.
    mutating func append(_ reading: PulseReading) {
        readings.append(reading)
    }
}

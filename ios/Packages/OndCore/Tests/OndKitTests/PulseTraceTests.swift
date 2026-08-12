import Foundation
@testable import OndKit
import Testing

/// What a session's readings become on the way to being a line.
///
/// Worth pinning because the drawing itself cannot be: it lives in the app
/// target, which has no test bundle, so every decision worth getting right —
/// what counts as enough readings, which way up the line goes, what a heart that
/// never moved draws as — is made here where it can be asserted.
@Suite("Pulse trace")
struct PulseTraceTests {
    private func trace(_ rates: [Int], everySeconds seconds: Int = 4) -> PulseTrace {
        PulseTrace(
            readings: rates.enumerated().map { index, rate in
                PulseReading(
                    elapsed: .seconds(index * seconds),
                    beatsPerMinute: rate
                )
            }
        )
    }

    @Test("A trace states the slowest and fastest it saw, and nothing else")
    func theRangeIsTheTwoEnds() {
        #expect(trace([78, 74, 69, 71, 64]).range == 64 ... 78)
        #expect(PulseTrace().range == nil)
    }

    /// Two readings drawn as a curve is a straight line between two numbers,
    /// which looks like a finding and is not one.
    @Test("Too few readings are not worth a drawing")
    func aHandfulIsNotACurve() {
        #expect(!PulseTrace().isWorthDrawing)
        #expect(!trace([78, 74]).isWorthDrawing)
        #expect(trace([78, 76, 74, 70, 68]).isWorthDrawing)
    }

    /// The whole point of the drawing: a heart that slowed has to come out as a
    /// line that descends, and the slowest reading is the one at the bottom.
    @Test("A settling heart draws from the top left to the bottom right")
    func aSettlingHeartFalls() {
        let points = trace([80, 76, 72, 68, 64]).points()

        #expect(points.count == 5)
        #expect(points.first?.x == 0)
        #expect(points.last?.x == 1)
        #expect(points.first?.y == 1, "the fastest reading sits at the top")
        #expect(points.last?.y == 0, "the slowest sits at the bottom")
        #expect(
            zip(points, points.dropFirst()).allSatisfy { $0.y > $1.y },
            "every step of a monotonic fall descends"
        )
    }

    /// Both axes are normalised to the session, so the x positions have to
    /// follow the clock rather than the count — a reading that arrived after a
    /// gap belongs where the gap put it, or the line silently redraws a dropped
    /// message as a steady rhythm.
    @Test("A gap in the readings is drawn as a gap")
    func timeRatherThanCount() {
        let readings = [0, 4, 8, 30, 40].map { second in
            PulseReading(elapsed: .seconds(second), beatsPerMinute: 70)
        }

        let points = PulseTrace(readings: readings).points()

        #expect(points.map(\.x) == [0, 0.1, 0.2, 0.75, 1])
    }

    /// A heart that held one rate has no spread to divide by. Level down the
    /// middle is the honest drawing of it — it neither fell nor rose — and the
    /// arithmetic must not answer with a division by zero.
    @Test("An unmoving heart draws level rather than crashing")
    func aFlatHeartIsFlat() {
        let flat = trace([70, 70, 70, 70, 70])

        #expect(flat.range == 70 ... 70)
        #expect(flat.points().allSatisfy { $0.y == 0.5 })
    }

    /// A trace whose readings all arrived at once has no span to spread them
    /// over. Nothing sensible can be drawn, and nothing may divide by nought.
    @Test("Readings with no time between them collapse rather than crash")
    func aZeroSpanIsSurvivable() {
        let readings = (0 ..< 5).map { _ in
            PulseReading(elapsed: .zero, beatsPerMinute: 70)
        }

        #expect(PulseTrace(readings: readings).points().allSatisfy { $0.x == 0 })
    }
}

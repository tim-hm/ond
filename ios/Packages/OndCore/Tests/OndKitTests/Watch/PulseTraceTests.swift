import Foundation
@testable import OndKit
import Testing

/// What a session's readings become on the way to being a line. Worth pinning
/// because the drawing itself cannot be: it lives in the app target, which has no
/// test bundle, so every decision worth getting right — what counts as enough
/// readings, which way up the line goes, what a heart that never moved draws as —
/// is made here where it can be asserted.
@Suite("Pulse trace")
struct PulseTraceTests {
    private func trace(_ rates: [Int], everySeconds seconds: Int = 8) -> PulseTrace {
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
    func aSettlingHeartFalls() throws {
        let points = try #require(trace([80, 76, 72, 68, 64]).runs().first)

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

    /// The x positions follow the clock rather than the count, so a reading
    /// that arrived late belongs where the delay put it — otherwise the line
    /// silently redraws a lost message as a steady rhythm. Every gap here is
    /// inside the staleness window, so it stays one unbroken run.
    @Test("Late readings are drawn late, not evenly")
    func timeRatherThanCount() throws {
        let readings = [0, 8, 16, 30, 40].map { second in
            PulseReading(elapsed: .seconds(second), beatsPerMinute: 70)
        }

        let points = try #require(PulseTrace(readings: readings).runs().first)

        #expect(points.map(\.x) == [0, 0.2, 0.4, 0.75, 1])
    }

    /// The defect this was built to fix: without a session length to draw
    /// against, a minute and a half of readings fills a fifteen-minute chart
    /// and reads as a heart that settled over the whole practice.
    @Test("A wrist that stopped early stops where it stopped")
    func theLineEndsWhereTheSharingDid() throws {
        var early = trace([78, 76, 74, 72, 70])
        early.close(at: .seconds(160))

        let points = try #require(early.runs().first)

        #expect(points.first?.x == 0)
        #expect(points.last?.x == 0.2, "thirty-two seconds of a session that ran for one sixty")
    }

    /// The ordinary case, and the reason the fallback is the last reading: a
    /// wrist that shared the whole way through reaches the right-hand edge
    /// whether or not anything told the trace how long the session was.
    @Test("A trace nothing closed draws to its own last reading")
    func anUnclosedTraceFillsTheChart() throws {
        let points = try #require(trace([78, 76, 74, 72, 70]).runs().first)

        #expect(points.last?.x == 1)
    }

    /// A pause ends the arrangement, so nothing is measured until it resumes.
    /// Joined up, those minutes draw as one straight segment across the middle
    /// of the chart — a heart rate nobody took, stated with exactly the
    /// confidence of the readings either side of it.
    @Test("A pause breaks the line rather than being drawn through")
    func aPauseBreaksTheLine() {
        let before = [0, 8, 16].map { second in
            PulseReading(elapsed: .seconds(second), beatsPerMinute: 78)
        }
        let after = [200, 208, 216].map { second in
            PulseReading(elapsed: .seconds(second), beatsPerMinute: 64)
        }

        let runs = PulseTrace(readings: before + after).runs()

        #expect(runs.count == 2, "the silence is a break, not a segment")
        #expect(runs.map(\.count) == [3, 3])
        #expect(runs[0].last?.x ?? 1 < runs[1].first?.x ?? 0, "and it is left where it happened")
    }

    /// A single reading on the far side of a silence is a dot a stroke cannot
    /// draw and a reader cannot place.
    @Test("A lone reading after a silence is dropped rather than drawn")
    func aLoneReadingIsNotARun() {
        let readings = [0, 8, 16, 24, 300].map { second in
            PulseReading(elapsed: .seconds(second), beatsPerMinute: 70)
        }

        let runs = PulseTrace(readings: readings).runs()

        #expect(runs.count == 1)
        #expect(runs[0].count == 4)
    }

    /// A heart that held one rate has no spread to divide by. Level down the
    /// middle is the honest drawing of it — it neither fell nor rose — and the
    /// arithmetic must not answer with a division by zero.
    @Test("An unmoving heart draws level rather than crashing")
    func aFlatHeartIsFlat() {
        let flat = trace([70, 70, 70, 70, 70])

        #expect(flat.range == 70 ... 70)
        #expect(flat.runs().flatMap(\.self).allSatisfy { $0.y == 0.5 })
    }

    /// A trace whose readings all arrived at once has no span to spread them
    /// over. Nothing sensible can be drawn, and nothing may divide by nought.
    @Test("Readings with no time between them collapse rather than crash")
    func aZeroSpanIsSurvivable() {
        let readings = (0 ..< 5).map { _ in
            PulseReading(elapsed: .zero, beatsPerMinute: 70)
        }

        #expect(PulseTrace(readings: readings).runs().flatMap(\.self).allSatisfy { $0.x == 0 })
    }
}

import Foundation
@testable import OndKit
import Testing

/// One phase, laid out on its own. Shared by both suites below, which ask
/// different questions of the same one-beat timeline.
private func beat(of phase: Phase) -> SessionTimeline.Beat? {
    SessionTimeline(stages: [Stage(phases: [phase], cycles: 1)], rounds: 1).beats.first
}

/// A phase can carry its own turn gap and its own spoken line instead of
/// letting the app work both out from the clock. Both halves are load-bearing
/// now that the catalogue authors tables: an authored value has to win
/// everywhere the derived one used to, and an absent one has to leave the
/// session exactly as it played before.
@Suite("A phase's authored cadence")
struct SessionCadenceTests {
    /// The rule the whole change rests on. Both halves in one test, because
    /// either alone would pass on an implementation that ignored the other.
    @Test("An authored gap is taken, and an absent one is worked out")
    func prefersTheAuthoredGap() throws {
        let authored = try #require(beat(of: Phase(
            .inhale(through: .nose),
            duration: .milliseconds(4000),
            turnGap: .milliseconds(450)
        )))
        let derived = try #require(beat(of: Phase(
            .inhale(through: .nose),
            duration: .milliseconds(4000)
        )))

        #expect(authored.turnGap == .milliseconds(450))
        #expect(derived.turnGap == .milliseconds(75), "the tempo rule, unchanged")
    }

    /// Zero is a value, not an absence — a continuous rhythm turns without a
    /// pause on purpose, and reading it as "say nothing" would put the tempo
    /// gap back on every phase of every exercise written that way.
    @Test("An authored zero means no gap, not no answer")
    func takesAnAuthoredZero() throws {
        let opening = try #require(beat(of: Phase(
            .inhale(through: .nose),
            duration: .milliseconds(4000),
            turnGap: .zero
        )))

        #expect(opening.turnGap == .zero)
        #expect(opening.breathing == opening.duration)
    }

    /// A dial can take a phase below the gap its table was written for. The
    /// sigh's sip dials to 500 ms and the ceiling is 600, so this is reachable
    /// rather than theoretical.
    @Test("An authored gap never takes more than half the phase")
    func capsAnAuthoredGapAgainstAShortPhase() throws {
        let opening = try #require(beat(of: Phase(
            .inhale(through: .nose),
            duration: .milliseconds(500),
            turnGap: .milliseconds(600)
        )))

        #expect(opening.turnGap == .milliseconds(250))
        #expect(opening.breathing == .milliseconds(250))
    }

    /// The stacked-breath pause is the other derived rule, and it widens the
    /// gap on the phase before a second breath in the same direction. A table
    /// that has already said how this turn goes must not be widened by it.
    @Test("A stacked breath does not widen an authored gap")
    func leavesAnAuthoredGapBeforeAStackedBreath() throws {
        let timeline = SessionTimeline(
            stages: [Stage(
                phases: [
                    Phase(
                        .inhale(through: .nose),
                        duration: .milliseconds(1500),
                        turnGap: .milliseconds(40)
                    ),
                    Phase(kind: .inhale, duration: .milliseconds(1000)),
                    Phase(kind: .exhale, duration: .milliseconds(5000)),
                ],
                cycles: 1
            )],
            rounds: 1
        )
        let opening = try #require(timeline.beats.first)

        #expect(opening.turnGap == .milliseconds(40), "not the 200 ms stacked pause")
        #expect(opening.stacksOnPrevious == false)
        #expect(timeline.beats[1].stacksOnPrevious)
    }

    /// The gap is borrowed from the phase, never inserted between two, so an
    /// authored one cannot lengthen a session past the dose the catalogue
    /// quotes. The same promise the derived gap already makes.
    @Test("An authored gap does not lengthen the session")
    func keepsTheDose() {
        let timeline = SessionTimeline(
            stages: [Stage(
                phases: [
                    Phase(
                        .inhale(through: .nose),
                        duration: .seconds(4),
                        turnGap: .milliseconds(600)
                    ),
                    Phase(.exhale(through: .nose), duration: .seconds(6), turnGap: .zero),
                ],
                cycles: 3
            )],
            rounds: 1
        )

        #expect(timeline.totalDuration == .seconds(30))
    }

    /// The condition that makes the seeded promise worth measuring. Alternate
    /// nostril authors a gap on all four of its phases, so it is where a gap
    /// inserted rather than borrowed would show first.
    /// `SessionTurnGapTests.keepsEverySeededDose` does the measuring.
    @Test("One seeded exercise authors a gap on every phase")
    func authorsAGapOnEveryPhaseOfOneTechnique() {
        let phases = SeededCatalogue.technique("alternate-nostril").stages.flatMap(\.phases)

        #expect(phases.count == 4)
        #expect(phases.allSatisfy { $0.turnGap != nil })
    }

    /// The seed writes this column as text and the client resolves it to a
    /// closed set, falling back to `standard` on anything else. That fallback
    /// is a quietly changed tap rather than a failure anybody sees, so a
    /// misspelling in the catalogue has to cost a test.
    @Test("Every seeded tap is one the client resolves")
    func seedsOnlyKnownHapticPatterns() {
        let patterns = SeededCatalogue.techniques
            .flatMap(\.stages)
            .flatMap(\.phases)
            .compactMap(\.hapticPattern)

        #expect(!patterns.isEmpty)
        #expect(patterns.allSatisfy { HapticPattern(rawValue: $0) != nil })
    }

    /// No table may ask for more of a phase than `maximumAuthoredShare`, or
    /// the beat is more stillness than breath. The layout caps a gap that
    /// does, so a table over the share plays as something other than what it
    /// says. Checked at the curated durations, which is where the app ships.
    @Test("No seeded gap takes more of its phase than a table may")
    func seedsGapsWithinTheAuthoredShare() {
        var checked = 0
        for technique in SeededCatalogue.techniques {
            for phase in technique.stages.flatMap(\.phases) {
                guard let gap = phase.turnGap else { continue }
                checked += 1
                #expect(
                    gap <= phase.duration * SessionTurnGap.maximumAuthoredShare,
                    "\(technique.slug)"
                )
            }
        }

        #expect(checked > 0, "a catalogue that failed to decode checks nothing")
    }
}

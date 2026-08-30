import Foundation
@testable import OndKit
import Testing

/// One phase, laid out on its own. Shared by both suites below, which ask
/// different questions of the same one-beat timeline.
private func beat(of phase: Phase) -> SessionTimeline.Beat? {
    SessionTimeline(stages: [Stage(phases: [phase], cycles: 1)], rounds: 1).beats.first
}

/// A phase can carry its own turn gap and its own spoken line instead of
/// letting the app work both out from the clock. Nothing in the catalogue
/// carries either yet, so the whole point of these tests is the fallback: an
/// absent value has to leave the session exactly as it played before, and an
/// authored one has to win everywhere the derived one used to.
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

    /// The state the app actually ships in. Every derived value in the session
    /// stays the one it has always been while this holds, so a table arriving
    /// in the seed is what should make somebody read the tests above.
    @Test("The seeded catalogue authors no cadence at all")
    func seedsNoCadence() {
        for technique in SeededCatalogue.techniques {
            for stage in technique.stages {
                for phase in stage.phases {
                    #expect(phase.turnGap == nil, "\(technique.slug)")
                    #expect(phase.hapticPattern == nil, "\(technique.slug)")
                    #expect(phase.voiceScript == nil, "\(technique.slug)")
                }
            }
        }
    }
}

/// Which clip a phase speaks. The sigh's three connected lines are the one
/// script the app already holds, and until now the only way to reach them was
/// to be a phase of the sigh. A table names the clip instead.
@Suite("A phase's authored line")
struct SessionVoiceScriptTests {
    @Test("An authored line is spoken, and an absent one is chosen")
    func prefersTheAuthoredLine() throws {
        let authored = try #require(beat(of: Phase(
            .inhale(through: .nose),
            duration: .seconds(4),
            voiceScript: "sigh-and-in"
        )))
        let derived = try #require(beat(of: Phase(
            .inhale(through: .nose),
            duration: .seconds(4)
        )))

        #expect(authored.clipStem == "sigh-and-in")
        #expect(derived.clipStem == "inhale", "the plain cue, unchanged")
    }

    /// A line still has to fit the phase it speaks into. An authored one is no
    /// different: a clip still playing after its phase ends names a breath
    /// nobody is taking, so the phase keeps its tone instead.
    @Test("An authored line too long for its phase falls to the tone")
    func fallsToTheToneWhereTheLineDoesNotFit() throws {
        let opening = try #require(beat(of: Phase(
            .inhale(through: .nose),
            duration: .milliseconds(200),
            voiceScript: "sigh-and-in"
        )))

        #expect(opening.spokenCue == .tone)
        #expect(opening.clipStem == nil)
    }

    /// A misspelled or retired clip name is not a line. Falling to the tone
    /// there would mute the phase for everybody, with nothing in the gate to
    /// say so — the column takes free text and no render checks it.
    @Test("A line naming no shipped clip leaves the ordinary cue standing")
    func ignoresALineNothingRendered() throws {
        let opening = try #require(beat(of: Phase(
            .inhale(through: .nose),
            duration: .seconds(4),
            voiceScript: "breath-in"
        )))

        #expect(opening.clipStem == "inhale")
        #expect(opening.spokenCue == .full)
    }

    /// The sigh reaches its connected lines through the cue role it is laid
    /// out with, and it still does. Nothing in the seed names a line, so this
    /// is the derivation the fallback protects.
    @Test("The seeded sigh still speaks its connected lines")
    func keepsTheSighsDerivedScript() {
        let timeline = SeededCatalogue.timeline("physiological-sigh")
        let stems = timeline.beats.prefix(3).map(\.clipStem)

        #expect(stems == ["sigh-in", "sigh-and-in", "sigh-and-out"])
    }
}

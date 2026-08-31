import Foundation
@testable import OndKit
import Testing

/// One line per exercise, thinning as the session goes on. Ten minutes of the
/// same sentence is worse than silence, so the first cycle teaches, the next
/// three prompt, and the rest is tone with the form cue every fourth time.
@Suite("How the voice thins")
struct VoiceThinningTests {
    @Test("The first cycle is taught in full")
    func theFirstCycleSpeaksTheSentence() {
        let beats = thinningSession(cycles: 12).beats.prefix(2)

        #expect(beats.map(\.clipStem) == ["inhale", "exhale"])
        #expect(beats.allSatisfy { $0.spokenCue == .full })
    }

    /// Two, three and four. The sentence has been heard once by then, and the
    /// word is enough to keep the rhythm.
    @Test("The next three cycles are cued in one word")
    func theEarlyCyclesSpeakTheWord() {
        let beats = thinningSession(cycles: 12).beats.filter { (1 ... 3).contains($0.cycle) }

        #expect(beats.count == 6)
        #expect(Set(beats.map(\.clipStem)) == ["short-in", "short-out"])
        #expect(beats.allSatisfy { $0.spokenCue == .short })
    }

    /// The state a long session spends most of itself in.
    @Test("From the fifth cycle the session takes the tone")
    func theLaterCyclesTakeTheTone() {
        let beats = thinningSession(cycles: 12).beats.filter { (4 ... 6).contains($0.cycle) }

        #expect(beats.count == 6)
        #expect(beats.allSatisfy { $0.clipStem == nil })
        #expect(beats.allSatisfy { $0.spokenCue == .tone })
    }

    /// On the longest phase of the cycle, and on that phase alone: the line
    /// teaches, so it needs the room the pattern has most of.
    @Test("Every fourth cycle teaches the form on the longest phase")
    func everyFourthCycleTeachesTheForm() throws {
        let timeline = thinningSession(cycles: 12)
        let eighth = timeline.beats.filter { $0.cycle == 7 }
        let teaching = try #require(eighth.first)

        #expect(eighth.map(\.clipStem) == ["hold", nil])
        #expect(teaching.spokenCue == .full)
    }

    /// The end is heard and not only felt. It outranks the form cue, which the
    /// twelfth cycle would otherwise take.
    @Test("The last cycle speaks the word again, both directions")
    func theLastCycleIsHeard() {
        let timeline = thinningSession(cycles: 12)
        let last = timeline.beats.filter(\.isFinalCycle)

        #expect(last.map(\.clipStem) == ["short-in", "short-out"])
        #expect(last.allSatisfy { $0.cycle == 11 })
    }

    /// A session of one cycle is both the first cycle and the last. The first
    /// wins: a person who hears one thing should hear the whole instruction.
    @Test("A session of one cycle is still taught in full")
    func oneCycleIsStillTheFirstCycle() {
        let beats = thinningSession(cycles: 1).beats

        #expect(beats.map(\.clipStem) == ["inhale", "exhale"])
        #expect(beats.map(\.isFinalCycle) == [true, true])
    }

    /// A line still has to fit the phase it speaks into, whatever the cycle
    /// says. Bellows breath runs a second each way and nothing but the tone
    /// fits there, which is the rule this schedule sits on top of.
    @Test("A cycle that calls for a line it cannot fit takes the tone")
    func theFitRuleStillWins() {
        let timeline = SessionTimeline(
            stages: [Stage(phases: [
                Phase(kind: .inhale, duration: .milliseconds(120)),
                Phase(kind: .exhale, duration: .milliseconds(120)),
            ], cycles: 12)],
            rounds: 1,
            formCue: "hold"
        )

        #expect(timeline.beats.allSatisfy { $0.clipStem == nil })
    }

    /// The reserved word, and the reason it had to be a word rather than an
    /// empty string: nothing else in the column can mean "say nothing", and a
    /// name the render never wrote falls back to the ordinary cue instead.
    @Test("A phase that asks for silence says nothing at any cycle")
    func silenceHoldsAtEveryCycle() {
        let timeline = thinningSession(cycles: 12, silencing: .inhale)
        // Every cycle but the eighth, which is the one that teaches the form.
        let inhales = timeline.beats.filter { $0.kind == .inhale && $0.cycle != 7 }

        #expect(inhales.count == 11)
        #expect(inhales.allSatisfy { $0.clipStem == nil })
        #expect(inhales.allSatisfy { $0.spokenCue == .tone })
    }

    /// The one line a silent table still speaks. It teaches rather than
    /// instructs, so it is not the second rhythm the silence was asked for.
    @Test("A silent phase still teaches the form")
    func silenceStillTeachesTheForm() throws {
        let timeline = thinningSession(cycles: 12, silencing: .inhale)
        let eighth = try #require(timeline.beats.first { $0.cycle == 7 })

        #expect(eighth.kind == .inhale)
        #expect(eighth.clipStem == "hold")
    }

    /// Three cycles of one stage, then two of another, twice over. The second
    /// stage counts 0, 1 in the first round and 2, 3 in the second: a stage is
    /// a different instruction and starts again, a round is a repeat and does
    /// not.
    @Test("The count starts again at a stage, and carries across a round")
    func theCountFollowsTheStage() {
        let timeline = SessionTimeline(
            stages: [
                Stage(phases: [Phase(kind: .inhale, duration: .seconds(4))], cycles: 3),
                Stage(phases: [Phase(kind: .exhale, duration: .seconds(4))], cycles: 2),
            ],
            rounds: 2
        )

        #expect(timeline.beats.map(\.stageCycle) == [0, 1, 2, 0, 1, 3, 4, 5, 2, 3])
        #expect(timeline.beats.map(\.cycle) == [0, 1, 2, 0, 1, 0, 1, 2, 0, 1])
        #expect(timeline.beats.filter(\.isFinalCycle).map(\.stageCycle) == [3])
    }

    /// The case the rule was changed for. A Wim Hof-style round opens each of
    /// its four stages with a different instruction, and each is said in full
    /// the first time the person reaches it.
    @Test("A stage that follows another speaks in full")
    func aNewStageIsTaught() {
        let technique = SeededCatalogue.technique("wim-hof-rounds")
        let beats = SessionTimeline(technique: technique).beats
        let openers = beats.filter { $0.stageCycle == 0 && $0.phase == 0 }

        #expect(openers.map(\.stage) == Array(0 ..< technique.stages.count))
        #expect(openers.allSatisfy { $0.round == 0 })
        #expect(openers.allSatisfy { $0.voiceDensity == .sentence })
    }

    /// Every exercise names its own, and it lands where the pattern has the
    /// most room — the six-second exhale, not the four-second inhale.
    @Test("An exercise names the form cue rendered for it")
    func aTechniqueNamesItsOwnFormCue() {
        let technique = SeededCatalogue.technique("extended-exhale")
        let teaching = SeededCatalogue.timeline("extended-exhale")
            .beats.filter { $0.formCue != nil }

        #expect(technique.formCue == "form-extended-exhale")
        #expect(!teaching.isEmpty)
        #expect(teaching.allSatisfy { $0.kind == .exhale })
        #expect(teaching.allSatisfy { $0.formCue == "form-extended-exhale" })
    }
}

/// Four seconds each way, so every line fits and only the schedule decides.
/// The form cue is a stem the render already shipped: the exercises' own are
/// not rendered yet, and a stem nothing matches is not a line.
private func thinningSession(cycles: Int, silencing silent: PhaseKind? = nil) -> SessionTimeline {
    func phase(_ kind: PhaseKind) -> Phase {
        Phase(
            Breath(kind: kind, through: Passage.nose),
            duration: .seconds(4),
            voiceScript: kind == silent ? VoiceClips.silentScript : nil
        )
    }
    return SessionTimeline(
        stages: [Stage(phases: [phase(.inhale), phase(.exhale)], cycles: cycles)],
        rounds: 1,
        formCue: "hold"
    )
}

/// Where speech starts, as against where the boundary is. The line has to be
/// running as the mark arrives, so it begins inside the stillness before it —
/// the gap the phase already borrowed, so nothing is spoken over.
@MainActor
@Suite("The line that leads the boundary")
struct SessionCueLeadTests {
    /// Four seconds each way, so every line fits and the gap is the tempo
    /// rule's 75 ms. `gap` is what separates the two tests: authored zero is
    /// the continuous rhythm, absent is the ordinary turn.
    private static func breathing(gap: Duration? = nil) -> Technique {
        Technique(
            id: "id",
            slug: "coherent-breathing",
            name: "Coherent Breathing",
            summary: "",
            goal: .calm,
            stages: [Stage(
                phases: [
                    Phase(.inhale(through: Passage.nose), duration: .seconds(4), turnGap: gap),
                    Phase(.exhale(through: Passage.nose), duration: .seconds(4), turnGap: gap),
                ],
                cycles: 4
            )],
            recommendedRounds: 1
        )
    }

    private func session(
        _ technique: Technique,
        cues: RecordingCues,
        on clock: ManualClock
    ) async throws -> SessionModel {
        let model = SessionModel(
            technique: technique,
            cues: cues,
            recorder: DiscardingRecorder(),
            clock: clock
        )
        model.start()
        try await waitFor("the first beat") { cues.played.count == 1 }
        return model
    }

    /// 75 ms is the tempo rule's gap for a four-second phase, so the second
    /// beat is spoken at 3925 ms and cued at 4000.
    @Test("The next line starts inside the gap before its boundary")
    func leadsTheBoundaryByTheGap() async throws {
        let clock = ManualClock()
        let cues = RecordingCues()
        let model = try await session(Self.breathing(), cues: cues, on: clock)

        clock.advance(by: .milliseconds(3925))
        try await waitFor("the next line to lead") { cues.spokenAhead.count == 1 }

        #expect(cues.spokenAhead.first?.id == 1)
        #expect(cues.played.count == 1, "the boundary itself has not arrived")

        model.end()
    }

    /// A rhythm authored to turn without a pause gets no lead: there is no
    /// stillness to speak into, and leading anyway would talk over the breath
    /// still being taken.
    @Test("A phase with no gap leads nothing")
    func aRhythmWithoutAGapIsNotLed() async throws {
        let clock = ManualClock()
        let cues = RecordingCues()
        let model = try await session(Self.breathing(gap: .zero), cues: cues, on: clock)

        clock.advance(by: .seconds(4))
        try await waitFor("the second beat") { cues.played.count == 2 }

        #expect(cues.spokenAhead.isEmpty)

        model.end()
    }
}

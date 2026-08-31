import Foundation
@testable import OndKit
import Testing

@Suite("Live Activity update cadence")
struct SessionActivityUpdatePolicyTests {
    private static let slow = Stage(
        phases: [
            Phase(kind: .inhale, duration: .seconds(4)),
            Phase(kind: .exhale, duration: .seconds(4)),
        ],
        cycles: 2
    )

    private static let rapid = Stage(
        phases: [
            Phase(kind: .inhale, duration: .seconds(1)),
            Phase(kind: .exhale, duration: .seconds(1)),
        ],
        cycles: 2
    )

    @Test("Slow breathing publishes every arriving phase")
    func slowBreathingPublishesEveryPhase() throws {
        let timeline = SessionTimeline(stages: [Self.slow], rounds: 1)
        let opening = try #require(timeline.beats.first)
        var policy = SessionActivityUpdatePolicy(status: .running, beat: opening)

        for beat in timeline.beats.dropFirst() {
            let shouldPublish = policy.shouldPublish(status: .running, beat: beat)
            #expect(shouldPublish)
        }
    }

    @Test("Rapid breathing skips interior phases but publishes a stage seam")
    func rapidBreathingPublishesOnlyTheSeam() throws {
        let timeline = SessionTimeline(stages: [Self.rapid, Self.rapid], rounds: 1)
        let opening = try #require(timeline.beats.first)
        var policy = SessionActivityUpdatePolicy(status: .running, beat: opening)

        let secondBeat = policy.shouldPublish(status: .running, beat: timeline.beats[1])
        let thirdBeat = policy.shouldPublish(status: .running, beat: timeline.beats[2])
        let fourthBeat = policy.shouldPublish(status: .running, beat: timeline.beats[3])
        let seam = policy.shouldPublish(status: .running, beat: timeline.beats[4])

        #expect(!secondBeat)
        #expect(!thirdBeat)
        #expect(!fourthBeat)
        #expect(seam)
        #expect(timeline.beats[4].opensStage)
    }

    @Test("A rapid rhythm publishes the seam between rounds")
    func rapidBreathingPublishesRoundSeam() throws {
        let timeline = SessionTimeline(stages: [Self.rapid], rounds: 2)
        let opening = try #require(timeline.beats.first)
        var policy = SessionActivityUpdatePolicy(status: .running, beat: opening)
        let published = timeline.beats.dropFirst().reduce(into: [Int]()) { result, beat in
            if policy.shouldPublish(status: .running, beat: beat) {
                result.append(beat.id)
            }
        }

        #expect(published == [4])
        #expect(timeline.beats[4].opensRound)
    }

    @Test("A hold within a rapid rhythm publishes its entry and exit")
    func rapidHoldPublishesEntryAndExit() {
        let rapidWithHold = Stage(
            phases: [
                Phase(kind: .inhale, duration: .seconds(1)),
                Phase(kind: .holdIn, duration: .seconds(1)),
                Phase(kind: .exhale, duration: .seconds(1)),
            ],
            cycles: 1
        )
        let timeline = SessionTimeline(stages: [rapidWithHold], rounds: 1)
        let opening = timeline.beats[0]
        let hold = timeline.beats[1]
        let exhale = timeline.beats[2]
        var policy = SessionActivityUpdatePolicy(status: .running, beat: opening)

        let enteredHold = policy.shouldPublish(status: .running, beat: hold)
        let leftHold = policy.shouldPublish(status: .running, beat: exhale)

        #expect(enteredHold)
        #expect(leftHold)
    }

    @Test("Pause, resume and completion publish without a phase change")
    func controlChangesPublish() throws {
        let timeline = SessionTimeline(stages: [Self.rapid], rounds: 1)
        let opening = try #require(timeline.beats.first)
        var policy = SessionActivityUpdatePolicy(status: .running, beat: opening)

        let paused = policy.shouldPublish(status: .paused, beat: opening)
        let resumed = policy.shouldPublish(status: .running, beat: opening)
        let finished = policy.shouldPublish(status: .finished, beat: nil)
        let duplicateFinish = policy.shouldPublish(status: .finished, beat: nil)

        #expect(paused)
        #expect(resumed)
        #expect(finished)
        #expect(!duplicateFinish)
    }
}

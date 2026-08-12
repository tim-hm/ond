import Foundation
@testable import OndKit
import Testing

/// The rules a session's mood check runs on — which taps count, what a skip
/// means, and when the check is done being asked.
///
/// Worth pinning because every one of them used to be a flag in a view, where
/// the failures are invisible: a second tap under a crossfade writing a
/// contradicting sample, a skip that re-asks, a countdown starting behind
/// Health's own authorization sheet.
@Suite("Mood check state")
@MainActor
struct MoodCheckModelTests {
    /// Records what reached Health, and holds the write open until it is let
    /// go — which is what makes the ordering assertions below possible.
    @MainActor
    private final class Writes {
        private(set) var moods: [Mood] = []
        var isBlocked = false

        func write(_ mood: Mood) async {
            while isBlocked {
                await Task.yield()
            }
            moods.append(mood)
        }
    }

    @Test("The pair is what the summary says back")
    func aPairReadsAsAPair() async {
        let check = MoodCheckModel()
        let writes = Writes()

        await check.answerBefore(.unpleasant, writing: writes.write)
        await check.answerAfter(.pleasant, writing: writes.write)

        #expect(check.note == "Unpleasant before · Pleasant now")
        #expect(writes.moods == [.unpleasant, .pleasant])
    }

    /// A single reading is still somebody's own record of how a practice left
    /// them, so the summary asks whether or not the way in was answered — and
    /// says the one word it has rather than inventing the other.
    @Test("A skipped way in leaves the reading standing alone")
    func aLoneReadingSaysItself() async {
        let check = MoodCheckModel()
        let writes = Writes()

        check.skipBefore()
        await check.answerAfter(.neutral, writing: writes.write)

        #expect(check.isAsked)
        #expect(check.before == nil)
        #expect(check.note == "Neutral")
        #expect(writes.moods == [.neutral], "a skip writes nothing; the answer after it does")
    }

    @Test("Nothing is said back until there is an answer to say")
    func silenceUntilAnswered() {
        #expect(MoodCheckModel().note == nil)
    }

    /// The check is the last gate before the countdown, and the first write of
    /// an install brings Health's own sheet with it. Clearing the gate before
    /// the write returns starts a session counting down behind a modal nobody
    /// asked to have opened.
    @Test("The check is not done being asked until the write comes back")
    func theGateWaitsForTheWrite() async {
        let check = MoodCheckModel()
        let writes = Writes()
        writes.isBlocked = true

        let answering = Task { await check.answerBefore(.pleasant, writing: writes.write) }
        while check.before == nil {
            await Task.yield()
        }

        #expect(check.before == .pleasant, "the scale fills in on the tap")
        #expect(!check.isAsked, "but the countdown is still held off")

        writes.isBlocked = false
        await answering.value

        #expect(check.isAsked)
    }

    /// The scale is on its way out under a crossfade and stays live for the
    /// length of it. Without the guard a corrective tap writes a contradicting
    /// sample beside the first, and nothing downstream could tell which one was
    /// meant.
    @Test("A second tap during the write changes nothing and writes nothing")
    func aMoodIsAnsweredOnce() async {
        let check = MoodCheckModel()
        let writes = Writes()

        await check.answerBefore(.pleasant, writing: writes.write)
        await check.answerBefore(.veryUnpleasant, writing: writes.write)
        await check.answerAfter(.neutral, writing: writes.write)
        await check.answerAfter(.veryPleasant, writing: writes.write)

        #expect(check.before == .pleasant)
        #expect(check.after == .neutral)
        #expect(writes.moods == [.pleasant, .neutral])
    }

    /// Skip is a button that has to do something the first time and nothing the
    /// second. It runs after an answer only in the gap before the gate clears,
    /// and it must not erase the answer that is already on its way to Health.
    @Test("Skipping after answering leaves the answer alone")
    func skippingCannotUndoAnAnswer() async {
        let check = MoodCheckModel()
        let writes = Writes()

        await check.answerBefore(.pleasant, writing: writes.write)
        check.skipBefore()

        #expect(check.before == .pleasant)
        #expect(check.isAsked)
        #expect(writes.moods == [.pleasant])
    }
}

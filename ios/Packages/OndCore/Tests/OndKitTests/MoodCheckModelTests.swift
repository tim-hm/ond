import Foundation
@testable import OndKit
import Testing

/// The rules a session's mood check runs on — which taps count, what declining
/// means, and when the check is done being asked.
///
/// Worth pinning because every one of them used to be a flag in a view, where
/// the failures are invisible: a second tap under a crossfade writing a
/// contradicting sample, a decline that re-asks, a countdown starting behind
/// Health's own authorization sheet.
@Suite("Mood check state")
@MainActor
struct MoodCheckModelTests {
    /// Records what reached Health, and holds the write open until it is let
    /// go — which is what makes the ordering assertions below possible.
    ///
    /// The block is bounded like `settle(until:)` is, and for its reason: a
    /// regression that stops the write ever being reached should fail with an
    /// assertion rather than spin the main actor for the length of the CI job.
    @MainActor
    private final class Writes {
        private(set) var moods: [Mood] = []
        var isBlocked = false

        func write(_ mood: Mood) async {
            for _ in 0 ..< 400 {
                guard isBlocked else { break }
                try? await Task.sleep(for: .milliseconds(5))
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

        #expect(check.note == "Not good before · Good now")
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
        #expect(check.note == "Okay")
        #expect(writes.moods == [.neutral], "a skip writes nothing; the answer after it does")
    }

    @Test("Nothing is said back until there is an answer to say")
    func silenceUntilAnswered() {
        #expect(MoodCheckModel().note == nil)
    }

    /// A requested check pauses the countdown, and the first write of an install
    /// brings Health's own sheet with it. Resolving the check before the write
    /// returns restarts a countdown behind a modal nobody asked to have opened.
    @Test("The check is not done being asked until the write comes back")
    func theGateWaitsForTheWrite() async throws {
        let check = MoodCheckModel()
        let writes = Writes()
        writes.isBlocked = true

        let answering = Task { await check.answerBefore(.pleasant, writing: writes.write) }
        try await settle { check.before != nil }

        #expect(check.before == .pleasant, "the scale fills in on the tap")
        #expect(!check.isAsked, "but the countdown is still held off")

        writes.isBlocked = false
        await answering.value

        #expect(check.isAsked)
    }

    /// A Health write can outlive the gesture that began it. Without the guard
    /// a corrective tap in that gap writes a contradicting sample beside the
    /// first, and nothing downstream could tell which one was meant.
    @Test("A second tap during the write changes nothing and writes nothing")
    func aMoodIsAnsweredOnce() async {
        let check = MoodCheckModel()
        let writes = Writes()

        await check.answerBefore(.pleasant, writing: writes.write)
        await check.answerBefore(.neutral, writing: writes.write)
        await check.answerAfter(.neutral, writing: writes.write)
        await check.answerAfter(.pleasant, writing: writes.write)

        #expect(check.before == .pleasant)
        #expect(check.after == .neutral)
        #expect(writes.moods == [.pleasant, .neutral])
    }

    @Test("Ignoring the invitation leaves the check unresolved")
    func ignoringChangesNothing() {
        let check = MoodCheckModel()

        #expect(!check.isAsked)
        #expect(check.before == nil)
        #expect(check.after == nil)
    }

    @Test("Not now resolves once without writing")
    func decliningIsOnceOnly() async {
        let check = MoodCheckModel()
        let writes = Writes()

        check.skipBefore()
        check.skipBefore()
        await check.answerBefore(.neutral, writing: writes.write)

        #expect(check.isAsked)
        #expect(check.before == nil)
        #expect(writes.moods.isEmpty)
    }

    /// Not now remains on screen while a selected answer waits for Health. It
    /// must neither erase that answer nor restart the countdown before the write
    /// and any first-use authorization sheet have finished.
    @Test("Declining during a write waits for the answer")
    func decliningCannotFinishAnAnswerEarly() async throws {
        let check = MoodCheckModel()
        let writes = Writes()
        writes.isBlocked = true

        let answering = Task { await check.answerBefore(.pleasant, writing: writes.write) }
        try await settle { check.before != nil }
        check.skipBefore()

        #expect(check.before == .pleasant)
        #expect(!check.isAsked)

        writes.isBlocked = false
        await answering.value

        #expect(check.isAsked)
        #expect(writes.moods == [.pleasant])
    }
}

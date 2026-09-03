import Foundation
@testable import OndKit
import Testing

/// What a session says when it ends. Every string here is a copy decision
/// argued in docs/product/session-summary.md, so a rewording that contradicts
/// the document fails rather than ships.
@Suite("Session summary lines")
struct SessionSummaryLinesTests {
    private func kept(completed: Bool = true) -> SessionSummaryLines.Outcome {
        .kept(record(completed: completed))
    }

    private func record(
        completed: Bool = true,
        cycles: Int = 4,
        breaths: Int = 8,
        lasting duration: Duration = .seconds(300)
    ) -> SessionRecord {
        SessionRecord(
            techniqueSlug: "box-breathing",
            startedAt: .now,
            duration: duration,
            cyclesCompleted: cycles,
            breathCount: breaths,
            completed: completed
        )
    }

    @Test("A finished session is celebrated and named")
    func aFinishedSessionIsNamed() {
        let session = kept()

        #expect(SessionSummaryLines.headline(for: session, register: .plain) == "All done.")
        #expect(SessionSummaryLines.note(for: session, exercise: "Box breathing", register: .plain)
            == "You finished Box breathing.")
    }

    /// The record's shape, stated and left there: no clause after it, and no
    /// verdict on the person who ended it.
    @Test("An early end is said as an early end")
    func anEarlyEndIsSaidPlainly() {
        let session = kept(completed: false)

        #expect(SessionSummaryLines.headline(for: session, register: .plain) == "All done.")
        #expect(SessionSummaryLines.note(for: session, exercise: "Box breathing", register: .plain)
            == "You ended this session early.")
    }

    /// The one line the note holds goes to the ending, not to the exercise:
    /// Progress names the exercise either way, and only this screen says how
    /// the session finished.
    @Test("An early end spends its line on the ending, not the exercise")
    func anEarlyEndDropsTheName() {
        let note = SessionSummaryLines.note(
            for: kept(completed: false),
            exercise: "Coherent 5.5",
            register: .plain
        )

        #expect(!note.contains("Coherent"))
    }

    /// The playful register is only reached through a moment breathed with a
    /// small child, so both lines are spoken to one. They state the record and
    /// pass no verdict on it, exactly as the plain pair does.
    @Test("The playful register says the same two facts to a child")
    func thePlayfulRegisterSpeaksToAChild() {
        let finished = kept()
        let stopped = kept(completed: false)

        #expect(SessionSummaryLines.headline(for: finished, register: .playful) == "You did it.")
        #expect(playfulNote(for: finished) == "You breathed Extended exhale together.")
        #expect(SessionSummaryLines.headline(for: stopped, register: .playful)
            == "That was breathing.")
        #expect(playfulNote(for: stopped) == "You stopped this one early.")
    }

    private func playfulNote(for outcome: SessionSummaryLines.Outcome) -> String {
        SessionSummaryLines.note(for: outcome, exercise: "Extended exhale", register: .playful)
    }

    /// The playful early end spends its one line on the ending too: the rule is
    /// the slot's, not the register's.
    @Test("A playful early end drops the exercise as the plain one does")
    func aPlayfulEarlyEndDropsTheName() {
        #expect(!playfulNote(for: kept(completed: false)).contains("Extended"))
    }

    /// A session ended inside the recording threshold is still told to the
    /// person: the screen it would otherwise skip is what makes the ending
    /// readable rather than a crash.
    @Test("A session too short to keep says so, and says nothing was kept")
    func aDiscardedSessionIsStillTold() {
        let note = SessionSummaryLines.note(
            for: .discarded,
            exercise: "Box breathing",
            register: .plain
        )

        #expect(SessionSummaryLines.headline(for: .discarded, register: .plain)
            == "Too short to keep.")
        #expect(note == "Nothing was recorded.")
    }

    /// One pair for both registers. There is no playful way to say that nothing
    /// was kept that does not make light of it.
    @Test("The playful register says the discarded pair plainly")
    func aDiscardedSessionKeepsThePlainWords() {
        #expect(SessionSummaryLines.headline(for: .discarded, register: .playful)
            == SessionSummaryLines.headline(for: .discarded, register: .plain))
        #expect(playfulNote(for: .discarded) == "Nothing was recorded.")
    }

    /// Progress speaks this figure in its history row, so the rule is measured
    /// once here rather than twice in two targets.
    @Test("A counted figure drops a zero and agrees its noun")
    func aCountedFigureAgreesItsNoun() {
        #expect(SessionSummaryLines.counted(0, of: "cycle") == nil)
        #expect(SessionSummaryLines.counted(1, of: "cycle")
            == SessionSummaryLines.Figure(label: "cycle", value: "1"))
        #expect(SessionSummaryLines.counted(19, of: "cycle")
            == SessionSummaryLines.Figure(label: "cycles", value: "19"))
    }

    @Test("Three figures, in reading order, when all three have something in them")
    func allThreeFiguresAreShown() {
        let figures = SessionSummaryLines.figures(for: record())

        #expect(figures.map(\.label) == ["cycles", "time", "breaths"])
        #expect(figures.map(\.value) == ["4", "5:00", "8"])
    }

    @Test("One of a thing is said in the singular")
    func singularsAreSingular() {
        let figures = SessionSummaryLines.figures(for: record(cycles: 1, breaths: 1))

        #expect(figures.map(\.label) == ["cycle", "time", "breath"])
    }

    /// A zero says nothing the time does not already say, and a row of them
    /// turns a screen that refuses to score into a scorecard.
    @Test("A figure with nothing in it is absent, and the time is not")
    func zeroesAreDropped() {
        let figures = SessionSummaryLines.figures(
            for: record(completed: false, cycles: 0, breaths: 0, lasting: .seconds(22))
        )

        #expect(figures.map(\.label) == ["time"])
        #expect(figures.map(\.value) == ["0:22"])
    }

    /// The middle figure counts whatever the session ran for, so it may not be
    /// labelled minutes: the sessions most likely to be read closely are the
    /// ones that never reached one.
    @Test("The time figure is labelled time")
    func theTimeIsLabelledTime() {
        let figures = SessionSummaryLines.figures(for: record(lasting: .seconds(45)))

        #expect(figures.contains(SessionSummaryLines.Figure(label: "time", value: "0:45")))
    }
}

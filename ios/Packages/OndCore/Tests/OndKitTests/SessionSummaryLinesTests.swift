import Foundation
@testable import OndKit
import Testing

/// What a session says when it ends. Every string here is a copy decision
/// argued in docs/product/session-summary.md, so a rewording that contradicts
/// the document fails rather than ships.
@Suite("Session summary lines")
struct SessionSummaryLinesTests {
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
        let session = record()

        #expect(SessionSummaryLines.headline(for: session) == "Nicely done.")
        #expect(SessionSummaryLines.note(for: session, exercise: "Box breathing")
            == "Box breathing, all the way through.")
    }

    /// The honesty clause Home's line is written under, said here too: the app
    /// states the shape of the record and passes no verdict on it.
    @Test("An early end is said as an early end")
    func anEarlyEndIsSaidPlainly() {
        let session = record(completed: false)

        #expect(SessionSummaryLines.headline(for: session) == "That's a session.")
        #expect(SessionSummaryLines.note(for: session, exercise: "Box breathing")
            == "Ended early — recorded as it happened.")
    }

    /// The one line the note holds goes to the ending, not to the exercise:
    /// Progress names the exercise either way, and only this screen says how
    /// the session finished.
    @Test("An early end spends its line on the ending, not the exercise")
    func anEarlyEndDropsTheName() {
        let note = SessionSummaryLines.note(for: record(completed: false), exercise: "Coherent 5.5")

        #expect(!note.contains("Coherent"))
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

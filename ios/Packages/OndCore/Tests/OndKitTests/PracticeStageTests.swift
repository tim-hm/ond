import Foundation
@testable import OndKit
import Testing

/// The ladder's rules, which are product rules before they are code: a rung is
/// earned by turning up, announced once, and never taken back.
@Suite("Practice stages")
struct PracticeStageTests {
    private func sessions(_ count: Int) -> [SessionRecord] {
        // Spread a day apart so the fold counts them as separate sessions on
        // separate days; only the count matters here.
        (0 ..< count).map { index in
            SessionRecord(
                techniqueSlug: "box-breathing",
                startedAt: Date(timeIntervalSince1970: 1_777_000_000 + Double(index) * 86400),
                duration: .seconds(120),
                cyclesCompleted: 4,
                breathCount: 8,
                completed: true
            )
        }
    }

    @Test("Nobody stands on a rung before their first session")
    func noRungBeforeTheFirstSession() {
        #expect(PracticeStage.held(atSessionCount: 0) == nil)
        #expect(JourneyStats.none.stage == nil)
    }

    @Test("The first session earns the first rung")
    func theFirstSessionEarnsTheFirstRung() {
        #expect(PracticeStage.reached(movingFrom: 0, to: 1) == .firstBreaths)
        #expect(PracticeStage.held(atSessionCount: 1) == .firstBreaths)
    }

    @Test("A rung holds until the next one is earned")
    func aRungHoldsUntilTheNextIsEarned() {
        #expect(PracticeStage.held(atSessionCount: 29) == .habitForming)
        #expect(PracticeStage.held(atSessionCount: 30) == .aPractice)
        #expect(PracticeStage.held(atSessionCount: 31) == .aPractice)
    }

    @Test("The last rung holds for good")
    func theLastRungHoldsForGood() {
        #expect(PracticeStage.held(atSessionCount: 10000) == .secondNature)
    }

    @Test("A rung is announced on the session that earns it, and not on the next")
    func aRungIsAnnouncedOnTheSessionThatEarnsIt() {
        for stage in PracticeStage.allCases {
            let earns = stage.sessionsNeeded
            #expect(PracticeStage.reached(movingFrom: earns - 1, to: earns) == stage)
            #expect(PracticeStage.reached(movingFrom: earns, to: earns + 1) == nil)
        }
    }

    /// What a restore does to the ladder, pinned so nobody reads the crossing
    /// rule as a promise that every rung gets a sentence.
    @Test("A rung passed by a restore is shown rather than announced")
    func aRungPassedByARestoreIsShownRatherThanAnnounced() {
        // Three sessions held; four arrive from the server in one merge. The
        // count passes 5 with no session finishing to say so.
        #expect(PracticeStage.reached(movingFrom: 3, to: 7) == .findingTheRhythm)
        // The session after it crosses nothing, so the summary stays quiet...
        #expect(PracticeStage.reached(movingFrom: 7, to: 8) == nil)
        // ...and the rung is standing on the Journey screen regardless.
        #expect(PracticeStage.held(atSessionCount: 8) == .findingTheRhythm)
    }

    /// Deleting history gives the rung up along with the sessions that earned
    /// it, so earning it again is a real crossing and says so again. The
    /// alternative is remembering a rung whose sessions were deleted, which is
    /// the residue this type refuses to keep.
    @Test("A rung given up by deleting history is announced again when re-earned")
    func aRungGivenUpIsAnnouncedAgain() {
        #expect(PracticeStage.reached(movingFrom: 4, to: 5) == .findingTheRhythm)
        // Deleted back below the threshold: the rung is genuinely not held.
        #expect(PracticeStage.held(atSessionCount: 4) == .firstBreaths)
        #expect(PracticeStage.reached(movingFrom: 4, to: 5) == .findingTheRhythm)
    }

    /// The property the whole design rests on: practising more can never move
    /// somebody down. Only deleting history can, and that is deletion doing what
    /// it says rather than the ladder taking something back.
    @Test("More practice never moves anybody down the ladder")
    func morePracticeNeverMovesAnybodyDown() {
        var previous: PracticeStage?
        for count in 0 ... (PracticeStage.secondNature.sessionsNeeded + 50) {
            guard let stage = PracticeStage.held(atSessionCount: count) else {
                #expect(count == 0)
                continue
            }
            if let previous {
                #expect(stage >= previous)
            }
            previous = stage
        }
    }

    @Test("Every rung has its own threshold, and they ascend")
    func rungsAreDistinctAndAscending() {
        let thresholds = PracticeStage.allCases.map(\.sessionsNeeded)
        #expect(thresholds == thresholds.sorted())
        #expect(Set(thresholds).count == thresholds.count)
        #expect(thresholds.allSatisfy { $0 > 0 })
    }

    @Test("The journey stands on the rung its session count has earned")
    func theJourneyStandsOnTheEarnedRung() {
        #expect(JourneyStats(sessions: sessions(1)).stage == .firstBreaths)
        #expect(JourneyStats(sessions: sessions(14)).stage == .findingTheRhythm)
        #expect(JourneyStats(sessions: sessions(15)).stage == .habitForming)
    }

    /// The copy rule as a tripwire rather than a promise. The list is the
    /// vocabulary of grading somebody — a rung that starts speaking it has
    /// turned the ladder into the thing this product is an alternative to.
    @Test("No rung's copy reads as a grade or a failure")
    func noRungReadsAsAGrade() {
        let graded = ["fail", "missed", "behind", "beginner", "novice", "expert", "rank", "should"]
        for stage in PracticeStage.allCases {
            let copy = "\(stage.title) \(stage.arrival)".lowercased()
            for word in graded {
                #expect(!copy.contains(word), "\(stage) says \"\(word)\"")
            }
        }
    }
}

/// The other half of the ladder: the session that reaches a rung, and what the
/// summary screen is told about it.
@MainActor
@Suite("Reaching a stage by finishing a session")
struct SessionStageTests {
    /// A store that already holds a history, and that dawdles inside `record`
    /// the way the shipping one does — `MindfulMinutesRecorder` asks Health for
    /// write access there, which is a system prompt the first time.
    private actor SeededRecorder: SessionRecording {
        private var sessions: [SessionRecord]
        private let delay: Duration

        init(holding count: Int, delayingRecordBy delay: Duration = .zero) {
            sessions = (0 ..< count).map { index in
                SessionRecord(
                    techniqueSlug: "box-breathing",
                    startedAt: Date(timeIntervalSince1970: 1_777_000_000 + Double(index) * 86400),
                    duration: .seconds(120),
                    cyclesCompleted: 4,
                    breathCount: 8,
                    completed: true
                )
            }
            self.delay = delay
        }

        var stored: [SessionRecord] {
            sessions
        }

        func record(_ session: SessionRecord) async {
            try? await Task.sleep(for: delay)
            sessions.append(session)
        }

        func remove(_: SessionRecord.ID) async {}

        func merge(_: [SessionRecord]) async -> Bool {
            false
        }

        func recordedSessions() async -> [SessionRecord] {
            sessions
        }
    }

    /// - Parameter cycles: two runs the plan out inside a test; a thousand
    ///   leaves it running for a test that wants to end one by hand.
    private func model(with recorder: any SessionRecording, cycles: Int = 2) -> SessionModel {
        SessionModel(
            technique: briefBreathing(cycles: cycles),
            cues: RecordingCues(),
            recorder: recorder
        )
    }

    @Test("The first session ever finished reaches the first rung")
    func theFirstSessionReachesTheFirstRung() async throws {
        let recorder = SeededRecorder(holding: 0)
        let session = model(with: recorder)

        session.start()
        try await waitFor("the plan to run out") { session.status == .finished }
        try await waitFor("the rung to land") { session.reachedStage != nil }

        #expect(session.reachedStage == .firstBreaths)
    }

    /// The regression the review found: the count is read before the record is
    /// handed over, so a recorder still waiting on Health cannot hold the
    /// announcement back past the screen it belongs on.
    @Test("The rung is known before the recorder has finished storing")
    func theRungDoesNotWaitOnTheRecorder() async throws {
        let recorder = SeededRecorder(holding: 0, delayingRecordBy: .seconds(5))
        let session = model(with: recorder)

        session.start()
        try await waitFor("the plan to run out") { session.status == .finished }
        try await waitFor("the rung to land") { session.reachedStage != nil }

        #expect(session.reachedStage == .firstBreaths)
        // Still inside `record`, so the answer cannot have come from a count
        // taken after it.
        #expect(await recorder.stored.isEmpty)
    }

    @Test("The session that crosses a threshold reaches that rung")
    func theSessionThatCrossesAThresholdReachesTheRung() async throws {
        let recorder = SeededRecorder(holding: 4)
        let session = model(with: recorder)

        session.start()
        try await waitFor("the plan to run out") { session.status == .finished }
        try await waitFor("the rung to land") { session.reachedStage != nil }

        #expect(session.reachedStage == .findingTheRhythm)
    }

    @Test("A session between rungs reaches nothing")
    func aSessionBetweenRungsReachesNothing() async throws {
        let recorder = SeededRecorder(holding: 40)
        let session = model(with: recorder)

        session.start()
        try await waitFor("the plan to run out") { session.status == .finished }
        // The rung is answered on the same Task that stores the record, so wait
        // for the store before reading "nothing" — otherwise the nil under test
        // is only the one it started with.
        try await waitFor("the record to be stored") { session.record != nil }
        // The model hands the record to the recorder and does not await it, so
        // the actor lands after the model does. Waiting on the count rather than
        // sleeping a fixed span: 50ms held right up until the suite ran this
        // beside 742 other tests, and then it did not.
        try await waitFor("the record to reach the store") {
            await recorder.stored.count == 41
        }

        #expect(session.reachedStage == nil)
        #expect(await recorder.stored.count == 41)
    }

    /// A false start never reaches the store, so it never reaches a rung either
    /// — the ladder counts practice, and the app has already decided this was
    /// not any.
    @Test("A false start reaches no rung")
    func aFalseStartReachesNoRung() async throws {
        let recorder = SeededRecorder(holding: 0)
        let session = model(with: recorder, cycles: 1000)

        session.start()
        try await Task.sleep(for: .milliseconds(40))
        session.end()

        #expect(session.wasDiscarded)
        try await Task.sleep(for: .milliseconds(50))
        #expect(session.reachedStage == nil)
        #expect(await recorder.stored.isEmpty)
    }
}

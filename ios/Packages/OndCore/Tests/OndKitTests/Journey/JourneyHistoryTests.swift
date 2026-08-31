import Foundation
@testable import OndKit
import Testing

/// What the journey tab draws of a history that only ever grows. The strip is
/// bounded and the numbers above it are not, and the split is the point: a
/// thousand-row history still expects totals and streak to count every row.
/// The cheap mistake is to bound the fold along with the drawing, silently
/// shrinking somebody's totals the day they crossed a page.
@MainActor
@Suite("The journey history strip")
struct JourneyHistoryTests {
    /// One page, as `JourneyModel` defines it. Written out rather than read off
    /// the model so a change to the page size has to be made deliberately here
    /// too — this is the number the screen's behaviour is described by.
    private static let page = 50

    private actor Store: SessionRecording, BoltScoreRecording {
        private var sessions: [SessionRecord]

        init(sessions: [SessionRecord]) {
            self.sessions = sessions
        }

        func record(_ session: SessionRecord) async {
            sessions.append(session)
        }

        func remove(_ id: SessionRecord.ID) async {
            sessions.removeAll { $0.id == id }
        }

        func recordedSessions() async -> [SessionRecord] {
            sessions
        }

        func merge(_: [SessionRecord]) async -> Bool {
            false
        }

        func record(_: BoltScore) async {}

        func recordedScores() async -> [BoltScore] {
            []
        }
    }

    /// Days apart, so "newest first" is a question the dates can answer.
    private func sessions(_ count: Int) -> [SessionRecord] {
        (0 ..< count).map { day in
            SessionRecord(
                techniqueSlug: "box-breathing",
                startedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(day) * 86400),
                duration: .seconds(120),
                cyclesCompleted: 4,
                breathCount: 8,
                completed: true
            )
        }
    }

    private func model(over sessions: [SessionRecord]) -> JourneyModel {
        let store = Store(sessions: sessions)
        // The shared spy, holding nothing: every test here is about what the
        // local fold draws, and the sync must not put anything back.
        let journeys = ServerSpy()
        let suite = "journey-history-tests.\(UUID().uuidString)"
        let ledger = SyncLedger(defaults: UserDefaults(suiteName: suite) ?? .standard)

        return JourneyModel(
            sessions: store,
            scores: store,
            rates: RateSpy(),
            journeys: journeys,
            queue: SessionSyncQueue(
                sessions: store,
                scores: store,
                rates: RateSpy(),
                journeys: journeys,
                ledger: ledger
            )
        )
    }

    @Test("The strip stops at a page while the totals count everything")
    func boundsTheStripAndNotTheFold() async {
        let recorded = sessions(Self.page * 2 + 7)
        let model = model(over: recorded)

        await model.refresh()

        #expect(model.visibleHistory.count == Self.page)
        #expect(model.stats.sessions == recorded.count)
        #expect(model.hasEarlierSessions)
        // It is the recent end the bound keeps: the newest session leads the
        // strip and the oldest is behind it, not the other way round.
        #expect(model.visibleHistory.first == recorded.last)
        #expect(!model.visibleHistory.contains(recorded[0]))
    }

    @Test("Revealing walks back through the history already in hand")
    func revealsAPageAtATime() async {
        let model = model(over: sessions(Self.page + 3))

        await model.refresh()
        model.revealEarlierSessions()

        #expect(Array(model.visibleHistory) == model.history)
        #expect(!model.hasEarlierSessions)
    }

    /// The ordinary case for most of an install's life: nothing to reveal, and
    /// therefore nothing on screen offering to.
    @Test("A history shorter than a page is shown whole")
    func showsAShortHistoryWhole() async {
        let model = model(over: sessions(4))

        await model.refresh()

        #expect(model.visibleHistory.count == 4)
        #expect(!model.hasEarlierSessions)
    }

    /// A delete refolds everything, and the strip must not roll back up under
    /// somebody who had just opened it.
    @Test("What has been revealed stays revealed across a refresh")
    func keepsTheRevealAcrossARefresh() async {
        let model = model(over: sessions(Self.page * 2))

        await model.refresh()
        model.revealEarlierSessions()
        await model.delete(model.history[0])

        #expect(model.visibleHistory.count == Self.page * 2 - 1)
    }
}

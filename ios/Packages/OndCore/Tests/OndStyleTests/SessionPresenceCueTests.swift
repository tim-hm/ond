import OndKit
@testable import OndStyle
import OndUI
import SwiftUI
import Testing

/// The cue rules the Live Activity surfaces draw from — pinned here because
/// the extension has no test bundle of its own, and a drift in these is the
/// lock screen and the Island marking one hold two ways.
@Suite("Pushed-surface cue rules")
struct SessionPresenceCueTests {
    private let accent = Color.orange

    @Test("a held breath cues the hold colour")
    func heldBreathTakesTheHoldColour() {
        #expect(SessionPresence.cueTint(breath: .holdIn, isPaused: false, over: accent)
            == Theme.Breath.hold)
        #expect(SessionPresence.cueTint(breath: .holdOut, isPaused: false, over: accent)
            == Theme.Breath.hold)
    }

    @Test("a moving breath keeps the surface's accent")
    func movingBreathKeepsTheAccent() {
        #expect(SessionPresence.cueTint(
            breath: .inhale(through: .nose), isPaused: false, over: accent
        ) == accent)
        #expect(SessionPresence.cueTint(
            breath: .exhale(through: .nose), isPaused: false, over: accent
        ) == accent)
    }

    @Test("pause suppresses the hold colour")
    func pauseSuppressesTheHoldColour() {
        #expect(SessionPresence.cueTint(breath: .holdIn, isPaused: true, over: accent) == accent)
    }

    @Test("the count runs down a plan-owned phase and up a retention")
    func countFollowsWhoOwnsThePhase() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let window = now ... now.addingTimeInterval(4)

        #expect(SessionPresence.cueCount(of: .breathing(window))
            == Text(timerInterval: window, countsDown: true))
        #expect(SessionPresence.cueCount(of: .holding(since: now))
            == Text(now, style: .timer))
    }

    @Test("a paused session counts nothing")
    func pausedSessionCountsNothing() {
        #expect(SessionPresence.cueCount(of: .paused) == nil)
    }

    @Test("only an exhale sweeps downward")
    func onlyAnExhaleCountsDown() {
        #expect(Breath.exhale(through: .nose).cueCountsDown)
        #expect(!Breath.inhale(through: .nose).cueCountsDown)
        #expect(!Breath.holdIn.cueCountsDown)
        #expect(!Breath.holdOut.cueCountsDown)
    }
}

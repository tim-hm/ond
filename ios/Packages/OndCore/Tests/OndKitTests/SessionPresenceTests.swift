import Foundation
@testable import OndKit
import Testing

/// What a running session says about itself to the lock screen and the Dynamic
/// Island.
///
/// Everything the Live Activity draws comes off `SessionPresence`, and none of
/// it can be seen on a host: `ActivityKit` is iOS-only and the rendering is the
/// system's. What *is* reachable here is the arithmetic that decides whether the
/// surface tells the truth — and every decision below is one that a simulator
/// would have shown as working.
///
/// Driven by a `ManualClock` so the wall-clock instants are exact, and read at a
/// fixed `now` so a window's width is the number this file put there rather than
/// a number plus however long the assertion took to run.
@MainActor
@Suite("A session as the lock screen sees it")
struct SessionPresenceTests {
    /// A four-second inhale and a six-second exhale — asymmetric on purpose, so
    /// a window's width names the phase it came from instead of matching either
    /// half of a box.
    private static let paced = Technique(
        id: "id",
        slug: "coherent-breathing",
        name: "Coherent Breathing",
        summary: "",
        goal: .calm,
        stages: [
            Stage(
                phases: [
                    Phase(kind: .inhale, duration: .seconds(4)),
                    Phase(kind: .exhale, duration: .seconds(6)),
                ],
                cycles: 100
            ),
        ],
        recommendedRounds: 1
    )

    /// All four phases in one cycle, because the compact Island's word is the
    /// only place both holds have to collapse to the same string.
    private static let boxed = Technique(
        id: "id",
        slug: "box-breathing",
        name: "Box Breathing",
        summary: "",
        goal: .focus,
        stages: [
            Stage(
                phases: [
                    Phase(kind: .inhale, duration: .seconds(4)),
                    Phase(kind: .holdIn, duration: .seconds(4)),
                    Phase(kind: .exhale, duration: .seconds(4)),
                    Phase(kind: .holdOut, duration: .seconds(4)),
                ],
                cycles: 100
            ),
        ],
        recommendedRounds: 1
    )

    /// Opens on a retention the person ends, which is the one phase whose length
    /// the plan does not know.
    private static let retention = Technique(
        id: "id",
        slug: "wim-hof-rounds",
        name: "Wim Hof-style Rounds",
        summary: "",
        goal: .energy,
        stages: [
            Stage(
                phases: [Phase(kind: .holdOut, duration: .seconds(60))],
                cycles: 1,
                openEnded: true
            ),
            Stage(phases: [Phase(kind: .inhale, duration: .seconds(4))], cycles: 1),
        ],
        recommendedRounds: 1
    )

    private static let sigh = Technique(
        id: "id",
        slug: "sigh",
        name: "Sigh",
        summary: "",
        goal: .reset,
        stages: [
            Stage(
                phases: [
                    Phase(kind: .inhale, duration: .milliseconds(1500)),
                    Phase(kind: .inhale, duration: .milliseconds(1000)),
                    Phase(kind: .exhale, duration: .milliseconds(5000)),
                ],
                cycles: 1
            ),
        ],
        recommendedRounds: 1
    )

    /// The instant every window below is measured against. Fixed at the
    /// reference date so the arithmetic is exact rather than exact to a
    /// float's breadth of a date in the eight-hundred-millions.
    private static let now = Date(timeIntervalSinceReferenceDate: 0)

    /// The invariant that keeps the ring honest. The window handed to the system
    /// is always the phase's whole length placed around the reading — so a
    /// reading taken three seconds in shifts it rather than shortening it, and
    /// the ring sweeps at the pace of the breath instead of at the pace of
    /// however stale the snapshot was. It is also what makes the range valid at
    /// all: a window derived from "now until the phase ends" would invert the
    /// moment a reading landed past the boundary.
    @Test("A phase's window is the phase's own length, wherever in it the reading lands")
    func theWindowIsTheWholePhase() async throws {
        let clock = ManualClock()
        let model = try await running(Self.paced, on: clock)

        let atTheTop = try #require(SessionPresence(of: model, at: Self.now))
        clock.advance(by: .seconds(3))
        let nearTheEnd = try #require(SessionPresence(of: model, at: Self.now))

        #expect(span(of: atTheTop) == 4, "the inhale is four seconds and the ring sweeps all of it")
        #expect(span(of: nearTheEnd) == 4, "a late reading shifts the window; it never shortens it")
        #expect(
            nearTheEnd.window?.contains(Self.now) == true,
            "the reading is inside its own phase, which is what makes the range valid"
        )
    }

    /// The expanded Island's trailing number is the whole plan, not the phase
    /// timer beside it in compact presentation. Running uses a wall-clock end so
    /// the system can count locally; pausing freezes the same duration.
    @Test("A finite session carries a live end and a paused remainder")
    func finiteSessionTiming() async throws {
        let clock = ManualClock()
        let model = try await running(Self.paced, on: clock)

        var presence = try #require(SessionPresence(of: model, at: Self.now))
        #expect(presence.sessionRemaining == .seconds(1000))
        #expect(presence.sessionEndsAt == Self.now.addingTimeInterval(1000))

        clock.advance(by: .seconds(3))
        model.pause()
        presence = try #require(SessionPresence(of: model, at: Self.now))

        #expect(presence.sessionRemaining == .seconds(997))
        #expect(presence.sessionEndsAt == nil)
    }

    /// A Live Activity can outlive the app build that created it. The timing
    /// fields therefore have to remain optional at the decoding boundary rather
    /// than making an already-visible activity unreadable after an update.
    @Test("A payload from before whole-session timing still decodes")
    func legacyPayloadWithoutSessionTiming() async throws {
        let clock = ManualClock()
        let model = try await running(Self.paced, on: clock)
        let current = try #require(SessionPresence(of: model, at: Self.now))
        let encoded = try JSONEncoder().encode(current)
        var object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "sessionEndsAt")
        object.removeValue(forKey: "sessionRemainingMilliseconds")

        let legacy = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(SessionPresence.self, from: legacy)

        #expect(decoded.instruction == current.instruction)
        #expect(decoded.sessionEndsAt == nil)
        #expect(decoded.sessionRemaining == nil)
    }

    /// A glance cue that goes on naming a phase nobody is breathing is the one
    /// failure it cannot afford, and a paused session is exactly when that
    /// happens. The phase itself is still carried — the resume needs it — so
    /// only the words change.
    @Test("A paused session stops naming a breath")
    func pausedSaysSo() async throws {
        let clock = ManualClock()
        let model = try await running(Self.paced, on: clock)
        model.pause()

        let presence = try #require(SessionPresence(of: model, at: Self.now))

        #expect(presence.instruction == "Paused")
        #expect(presence.spokenInstruction == "Paused")
        #expect(
            presence.cueWord == nil,
            "the compact region draws the pause glyph on this, as it does on a nil count"
        )
        #expect(presence.breath.kind == .inhale, "the phase is kept; only the words change")
        #expect(
            presence.caption(of: "Box Breathing") == "Box Breathing",
            "a stopped session captioned with a hint asserts a breath nobody is taking"
        )
    }

    /// The lock screen's second line: what is being practised, and how.
    ///
    /// The glance form, because this sits beside a technique name on one line —
    /// "Cooling Breath · Through a curled tongue" is a caption that wraps, and a
    /// wrapped caption on a lock screen is one somebody reads none of.
    @Test("The caption names the technique and how the breath is shaped")
    func theCaptionNamesTheShape() async throws {
        let clock = ManualClock()
        let model = try await running(SeededCatalogue.technique("cooling-breath"), on: clock)

        let presence = try #require(SessionPresence(of: model, at: Self.now))

        #expect(presence.caption(of: "Cooling Breath") == "Cooling Breath · Curled tongue")
    }

    /// A technique with nothing to add captions its own name and nothing else —
    /// the case that keeps the separator from becoming permanent furniture.
    @Test("A caption with no hint is the technique name alone")
    func aCaptionWithNoHintIsTheNameAlone() async throws {
        let clock = ManualClock()
        let model = try await running(SeededCatalogue.technique("coherent-breathing"), on: clock)

        let presence = try #require(SessionPresence(of: model, at: Self.now))

        #expect(presence.caption(of: "Coherent Breathing") == "Coherent Breathing")
    }

    /// The Live Activity crosses a process boundary, so carrying only the
    /// breath would collapse the sigh back to three standalone instructions.
    @Test("A sigh keeps its connected wording outside the app")
    func sighKeepsItsConnectedWording() async throws {
        let clock = ManualClock()
        let model = try await running(Self.sigh, on: clock)

        var presence = try #require(SessionPresence(of: model, at: Self.now))
        #expect(presence.instruction == "Breathe in")

        clock.advance(by: .milliseconds(1500))
        try await waitFor("the sigh's top-up") { model.currentBeat?.id == 1 }
        presence = try #require(SessionPresence(of: model, at: Self.now))
        #expect(presence.instruction == "And in")
        #expect(presence.spokenInstruction == "And in")

        let encoded = try JSONEncoder().encode(presence)
        let decoded = try JSONDecoder().decode(SessionPresence.self, from: encoded)
        #expect(decoded.instruction == "And in")

        clock.advance(by: .milliseconds(1000))
        try await waitFor("the sigh's release") { model.currentBeat?.id == 2 }
        presence = try #require(SessionPresence(of: model, at: Self.now))
        #expect(presence.instruction == "And breathe out")
        #expect(presence.spokenInstruction == "And breathe out")
        #expect(
            presence.cueWord == "Out",
            "the connective wording is a sentence, and the compact region fits a word"
        )
    }

    /// The compact Dynamic Island is about a word wide, so the phase arrives as
    /// one — beside a ring that already says how far through it is. Both holds
    /// give the same word on purpose: "Hold, lungs empty" is a sentence, and the
    /// region it would have to fit is two characters wider than "Hold".
    @Test("The compact Island gets the phase in one word")
    func theCompactIslandGetsOneWord() async throws {
        let clock = ManualClock()
        let model = try await running(Self.boxed, on: clock)

        var presence = try #require(SessionPresence(of: model, at: Self.now))
        #expect(presence.cueWord == "In")

        for (beat, word) in [(1, "Hold"), (2, "Out"), (3, "Hold")] {
            clock.advance(by: .seconds(4))
            try await waitFor("phase \(beat)") { model.currentBeat?.id == beat }
            presence = try #require(SessionPresence(of: model, at: Self.now))
            #expect(presence.cueWord == word)
        }
    }

    /// What takes the Activity off the lock screen. `SessionActivity` ends it on
    /// the first refresh that has nothing to show, so "nothing to show" has to be
    /// exactly the two moments a session is not running — anything else leaves a
    /// cue up after the breathing has stopped.
    @Test("There is nothing to show before a session begins or after it ends")
    func nothingOutsideTheSession() async throws {
        let model = SessionModel(
            technique: Self.paced,
            cues: RecordingCues(playsInBackground: true),
            recorder: DiscardingRecorder(),
            clock: ManualClock()
        )

        #expect(SessionPresence(of: model, at: Self.now) == nil, "it has not been started")

        model.start()
        try await waitFor("the first phase") { model.currentBeat != nil }
        model.end()

        #expect(SessionPresence(of: model, at: Self.now) == nil, "and this is what ends the cue")
    }

    /// The one place the session's two clocks come apart, seen from this
    /// surface. During an open-ended hold the plan is pinned at the hold's
    /// start, so a stance derived from `elapsed` would date every retention to
    /// this instant — a lock-screen timer stuck at zero for as long as somebody
    /// held their breath. Only the hold's own clock knows.
    @Test("A retention is dated from when it began, not from the plan it stopped")
    func holdKeepsItsOwnClock() async throws {
        let clock = ManualClock()
        let model = SessionModel(
            technique: Self.retention,
            cues: RecordingCues(playsInBackground: true),
            recorder: DiscardingRecorder(),
            clock: clock
        )
        model.start()
        try await waitFor("the retention to begin") { model.status == .holding }
        clock.advance(by: .seconds(20))

        let presence = try #require(SessionPresence(of: model, at: Self.now))

        guard case let .holding(since) = presence.stance else {
            Issue.record("a retention is held, not breathed: \(presence.stance)")
            return
        }
        #expect(Self.now.timeIntervalSince(since) == 20)
        // The lock screen swaps Pause for "I'm ready" on this, because nothing
        // else can advance a phase the person ends.
        #expect(presence.isHolding)
        #expect(presence.window == nil, "a retention has no end for a ring to sweep towards")
        // The instant the lock screen counts up from, and the same instant its
        // cue label speaks as a value — one derivation, so the drawn number and
        // the read number cannot come apart.
        #expect(presence.heldSince == since)
    }

    /// A session on a clock nothing but the test moves, already inside its first
    /// phase.
    private func running(
        _ technique: Technique,
        on clock: ManualClock
    ) async throws -> SessionModel {
        let model = SessionModel(
            technique: technique,
            cues: RecordingCues(playsInBackground: true),
            recorder: DiscardingRecorder(),
            clock: clock
        )
        model.start()
        try await waitFor("the first phase") { model.currentBeat != nil }
        return model
    }

    private func span(of presence: SessionPresence) -> TimeInterval? {
        presence.window.map { $0.upperBound.timeIntervalSince($0.lowerBound) }
    }
}

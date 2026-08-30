import OndKit
import Testing

private typealias Transient = SessionHapticShape.Transient

private func beats(_ phases: [Phase]) -> [SessionTimeline.Beat] {
    SessionTimeline(stages: [Stage(phases: phases, cycles: 1)], rounds: 1).beats
}

private func phase(_ kind: PhaseKind, _ duration: Duration, pattern: String? = nil) -> Phase {
    Phase(Breath(kind: kind, through: .nose), duration: duration, hapticPattern: pattern)
}

private let wholeCycle = [
    Phase(kind: .inhale, duration: .seconds(4)),
    Phase(kind: .holdIn, duration: .seconds(4)),
    Phase(kind: .exhale, duration: .seconds(4)),
    Phase(kind: .holdOut, duration: .seconds(4)),
]

/// The authored phase shapes both device renderers promise to preserve.
@Suite("Session haptic shapes")
struct SessionHapticShapeTests {
    @Test("A full breath keeps the phone's tuned envelope endpoints")
    func fullBreathEndpoints() throws {
        let cycle = beats(wholeCycle)
        let inhale = try #require(SessionHapticShape(beat: cycle[0]).envelope)
        let exhale = try #require(SessionHapticShape(beat: cycle[2]).envelope)

        #expect([inhale.startIntensity, inhale.endIntensity, inhale.sharpness]
            == [0.12, 0.85, 0.3])
        #expect([exhale.startIntensity, exhale.endIntensity, exhale.sharpness]
            == [0.8, 0.08, 0.1])
    }

    @Test("Every phase opens on a mark")
    func everyPhaseHasAnOnset() {
        let onsets = beats(wholeCycle).map { SessionHapticShape(beat: $0).onset }

        #expect(onsets == [
            Transient(intensity: 0.55, sharpness: 0.65),
            Transient(intensity: 0.9, sharpness: 0.8),
            Transient(intensity: 0.45, sharpness: 0.25),
            Transient(intensity: 0.45, sharpness: 0.1),
        ])
    }

    /// The rule the strength setting must not be able to break. It shifts every
    /// sharpness by the same amount, so an order that holds at one setting
    /// holds at all three.
    @Test("Every mark on the way in stays sharper than every mark on the way out")
    func directionSurvivesTheStrengthSetting() {
        let marked = beats([
            Phase(kind: .inhale, duration: .seconds(4)),
            Phase(kind: .inhale, duration: .seconds(1)),
            Phase(kind: .holdIn, duration: .seconds(4)),
            Phase(kind: .exhale, duration: .seconds(4)),
            Phase(kind: .holdOut, duration: .seconds(4)),
        ])
        let sharpness = marked.map { SessionHapticShape(beat: $0).onset.sharpness }

        for strength in HapticStrength.allCases {
            let scaled = sharpness.map(strength.sharpness)
            #expect((scaled[0 ... 2].min() ?? 0) > (scaled[3 ... 4].max() ?? 1), "\(strength)")
        }
    }

    /// The one asymmetry in the design that carries meaning: a hold at the top
    /// is something you are doing, a hold at the bottom something you are not.
    @Test("Hold-in is the firmest mark and hold-out the softest")
    func holdsStayAsymmetric() throws {
        let marks = beats(wholeCycle).map { SessionHapticShape(beat: $0).onset.intensity }
        let softest = try #require(marks.min())

        #expect(marks[1] == marks.max())
        #expect(marks[3] == softest)
        // The floor `HapticStrength` keeps is there for this phase.
        #expect(HapticStrength.gentle.intensity(softest) > 0)
    }

    @Test("Both holds fall silent after their mark")
    func holdsAreSilentAfterTheirMark() {
        let cycle = beats(wholeCycle)

        #expect(SessionHapticShape(beat: cycle[1]).envelope == nil)
        #expect(SessionHapticShape(beat: cycle[3]).envelope == nil)
    }

    @Test("The envelope opens after the mark and stops before the boundary")
    func envelopeLeavesBothEndsQuiet() throws {
        let inhale = beats(wholeCycle)[0]
        let span = try #require(SessionHapticShape(beat: inhale).envelope?.span)

        #expect(span.lowerBound == .milliseconds(300))
        #expect(span.upperBound == inhale.breathing - .milliseconds(300))
        #expect(span.upperBound < inhale.duration)
    }

    @Test("A phase with no room left keeps its mark and drops the movement")
    func shortPhaseKeepsOnlyItsMark() {
        let brief = beats([Phase(kind: .inhale, duration: .milliseconds(500))])[0]
        let shape = SessionHapticShape(beat: brief)

        #expect(shape.envelope == nil)
        #expect(shape.onset == Transient(intensity: 0.55, sharpness: 0.65))
    }

    @Test("A stacked inhale authors only its final top-up")
    func stackedInhale() throws {
        let sigh = beats([
            Phase(kind: .inhale, duration: .milliseconds(1500)),
            Phase(kind: .inhale, duration: .milliseconds(700)),
            Phase(kind: .exhale, duration: .seconds(5)),
        ])
        let sip = SessionHapticShape(beat: sigh[1])
        let envelope = try #require(sip.envelope)

        #expect(envelope.startIntensity > 0.75)
        #expect(envelope.startIntensity < envelope.endIntensity)
        #expect(envelope.endIntensity == 0.85)
        #expect(envelope.sharpness == 0.3)
        #expect(sip.onset == Transient(intensity: 0.4, sharpness: 0.75))
    }
}

/// The five ids the catalogue's haptic pattern column may name, and what an id
/// nothing knows falls back to.
@Suite("Haptic patterns")
struct HapticPatternTests {
    private func breath(pattern: String?) -> [Phase] {
        [
            phase(.inhale, .seconds(4), pattern: pattern),
            phase(.exhale, .seconds(4), pattern: pattern),
        ]
    }

    private func playsTheSame(_ named: String?, as other: String?) -> Bool {
        zip(beats(breath(pattern: named)), beats(breath(pattern: other))).allSatisfy {
            SessionHapticShape(beat: $0) == SessionHapticShape(beat: $1)
        }
    }

    /// Every seeded phase names nothing, so this is the whole of what the
    /// shipped catalogue plays.
    @Test("A phase naming no pattern plays exactly what standard plays")
    func nilIsStandard() {
        #expect(beats(breath(pattern: nil)).allSatisfy { $0.hapticPattern == .standard })
        #expect(playsTheSame(nil, as: "standard"))
    }

    @Test("An id this build does not know falls back to standard")
    func unknownIdFallsBack() {
        #expect(beats(breath(pattern: "cascade")).allSatisfy { $0.hapticPattern == .standard })
        #expect(playsTheSame("cascade", as: "standard"))
    }

    @Test("Sip states the stacked mark rather than inheriting it by accident")
    func sipMarksAStackedInhale() {
        let sigh = beats([
            Phase(kind: .inhale, duration: .milliseconds(1500)),
            Phase(kind: .inhale, duration: .milliseconds(700)),
        ])
        let named = beats([phase(.inhale, .milliseconds(700), pattern: "sip")])[0]

        #expect(named.hapticPattern == .sip)
        #expect(SessionHapticShape(beat: named).onset == SessionHapticShape(beat: sigh[1]).onset)
        #expect(SessionHapticShape(beat: named).onset != SessionHapticShape(beat: sigh[0]).onset)
    }

    @Test("Press firms the mark and holds the envelope instead of decaying")
    func pressHoldsItsLevel() throws {
        let pressed = beats([phase(.exhale, .seconds(4), pattern: "press")])[0]
        let shape = SessionHapticShape(beat: pressed)
        let envelope = try #require(shape.envelope)

        #expect(shape.onset == Transient(intensity: 0.6, sharpness: 0.35))
        #expect(envelope.startIntensity == 0.5)
        #expect(envelope.endIntensity == 0.5)
    }

    @Test("Drum is the mark and nothing else, on both devices")
    func drumIsOnsetOnly() {
        let drummed = beats([phase(.inhale, .seconds(1), pattern: "drum")])[0]
        let shape = SessionHapticShape(beat: drummed)

        #expect(shape.onset == Transient(intensity: 0.55, sharpness: 0.65))
        #expect(shape.envelope == nil)
        #expect(WatchHapticStyle().pulses(for: drummed).isEmpty)
    }

    @Test("A long hold is reminded it is still running")
    func longHoldReminds() throws {
        let held = beats([phase(.holdOut, .seconds(90), pattern: "long-hold")])[0]
        let reminder = try #require(SessionHapticShape(beat: held).reminder)
        let ordinary = beats([phase(.holdOut, .seconds(7))])[0]

        #expect(held.hapticPattern == .longHold)
        #expect(reminder.tap == Transient(intensity: 0.35, sharpness: 0.6))
        #expect(reminder.interval == .seconds(15))
        #expect(SessionHapticShape(beat: ordinary).reminder == nil)
    }
}

import Foundation
import OndAPI
@testable import OndKit
import Testing

/// The limits a composer draws its dials from, coming off the wire.
///
/// The one decoder in the package whose guards stand between a malformed
/// response and a *crash* rather than a wrong drawing: `AuthoringLimits` builds
/// two `ClosedRange`s out of counts the contract leaves unconstrained, and
/// `ClosedRange` traps on a lower bound above its upper one. A zero count or an
/// inverted range therefore has to fail as a decode, on the device, before the
/// range is formed.
///
/// The server pins its own half — `the_authoring_limits_come_from_the_seeded_ranges`
/// in `crates/api/tests/e2e/user_technique.rs` — which is precisely what leaves
/// this half unheld: a seed or proto change that let a zero through would be
/// answered here by a launch crash in the composer.
@Suite("Reading the authoring limits off the wire")
struct UserTechniqueDecodingTests {
    private static func phaseLimit(
        _ kind: Ond_V1_PhaseKind,
        _ minDurationMs: UInt32 = 1000,
        _ maxDurationMs: UInt32 = 10000
    ) -> Ond_V1_PhaseLimit {
        var limit = Ond_V1_PhaseLimit()
        limit.kind = kind
        limit.minDurationMs = minDurationMs
        limit.maxDurationMs = maxDurationMs
        return limit
    }

    /// A message shaped like the seed's, so every test below changes exactly the
    /// one thing it is about.
    private static func limits(
        phases: [Ond_V1_PhaseLimit] = [phaseLimit(.inhale), phaseLimit(.exhale)]
    ) -> Ond_V1_AuthoringLimits {
        var limits = Ond_V1_AuthoringLimits()
        limits.phases = phases
        limits.maxNameChars = 40
        limits.maxSummaryChars = 120
        limits.maxStages = 4
        limits.maxPhasesPerStage = 6
        limits.maxCycles = 30
        limits.maxRounds = 10
        limits.maxTechniques = 20
        return limits
    }

    @Test("A well-formed message arrives with its ranges intact")
    func decodesTheSeededShape() throws {
        let limits = try AuthoringLimits(proto: Self.limits())

        #expect(limits.cycleRange == 1 ... 30)
        #expect(limits.roundRange == 1 ... 10)
        #expect(limits.maxTechniques == 20)
        #expect(limits.range(for: .inhale) == .milliseconds(1000) ... .milliseconds(10000))
        #expect(limits.range(for: .holdIn) == nil, "a kind the message never named")
    }

    /// Each count separately, because the guard is one `guard` over seven fields
    /// and a dropped condition would be invisible in any single case. Two of
    /// them — the cycles and the rounds — become `ClosedRange` bounds a line
    /// later, so a zero there is the trap itself; the rest are steppers and text
    /// fields nobody can compose against.
    @Test("A count of zero leaves nothing to compose, whichever count it is")
    func refusesAZeroCount() {
        let counts: [(String, WritableKeyPath<Ond_V1_AuthoringLimits, UInt32>)] = [
            ("max_name_chars", \.maxNameChars),
            ("max_summary_chars", \.maxSummaryChars),
            ("max_stages", \.maxStages),
            ("max_phases_per_stage", \.maxPhasesPerStage),
            ("max_cycles", \.maxCycles),
            ("max_rounds", \.maxRounds),
            ("max_techniques", \.maxTechniques),
        ]

        for (field, count) in counts {
            var zeroed = Self.limits()
            zeroed[keyPath: count] = 0

            #expect(throws: UserTechniqueRepositoryError.self, "a zero \(field) is composable") {
                try AuthoringLimits(proto: zeroed)
            }
        }
    }

    /// The trap this suite exists for. A phase limit whose minimum is above its
    /// maximum is not a narrow dial, it is `ClosedRange.init` calling
    /// `precondition` — so this has to be a thrown error rather than a clamp,
    /// and the whole limits message fails with it.
    @Test("An inverted duration range is refused rather than formed")
    func refusesAnInvertedRange() {
        let inverted = Self.limits(phases: [Self.phaseLimit(.inhale, 10000, 1000)])

        #expect(throws: UserTechniqueRepositoryError.self) {
            try AuthoringLimits(proto: inverted)
        }
    }

    /// Zero is the proto default, so this is what a server that stopped setting
    /// the field sends — and a phase dialled to nothing is a session that never
    /// leaves the first breath.
    @Test("A range starting at nothing is refused too")
    func refusesAZeroMinimum() {
        let empty = Self.limits(phases: [Self.phaseLimit(.inhale, 0, 10000)])

        #expect(throws: UserTechniqueRepositoryError.self) {
            try AuthoringLimits(proto: empty)
        }
    }

    /// Both unreadable wire values, because they are the same fact to a
    /// composer: a kind whose dial this build cannot draw. Dropping the limit
    /// instead would leave the composer offering that kind with no range at all,
    /// which `clamping` reads as a phase it must not touch — so a safe duration
    /// the server enforces would go unenforced on the dial.
    @Test("A phase kind this build cannot name fails the whole message")
    func refusesAnUnreadablePhaseKind() {
        for kind in [Ond_V1_PhaseKind.UNRECOGNIZED(42), .unspecified] {
            let unreadable = Self.limits(phases: [Self.phaseLimit(kind)])

            #expect(throws: UserTechniqueRepositoryError.self, "\(kind) is not a phase kind") {
                try AuthoringLimits(proto: unreadable)
            }
        }
    }
}

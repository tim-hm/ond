import Foundation
@testable import OndKit
import Testing

/// The launch funnel's domain decisions, with no app target or SwiftUI host.
@MainActor
@Suite("Session launch resolver")
struct SessionLaunchResolverTests {
    private static let technique = Technique(
        id: "id",
        slug: "box-breathing",
        name: "Box Breathing",
        summary: "",
        goal: .calm,
        stages: [
            Stage(
                phases: [
                    Phase(kind: .inhale, duration: .seconds(4)),
                    Phase(kind: .exhale, duration: .seconds(4)),
                ],
                cycles: 4
            ),
        ],
        recommendedRounds: 1
    )

    private func resolver(cuesMade: Counter = Counter()) -> SessionLaunchResolver {
        SessionLaunchResolver(sessions: DiscardingRecorder()) {
            cuesMade.value += 1
            return RecordingCues()
        }
    }

    /// Entitlement is checked before the surface, so a locked discreet stop
    /// cannot bypass the catalogue gate by being handed to another device.
    @Test("A locked technique asks for its subscription before making cues or a handoff")
    func lockedTechniqueRequiresItsTier() {
        let cuesMade = Counter()
        let locked = Technique(
            id: "locked",
            slug: "locked",
            name: "Locked",
            summary: "",
            goal: .calm,
            stages: Self.technique.stages,
            recommendedRounds: 1,
            requires: .plus
        )
        let stop = discreetStop(for: locked)

        guard case let .subscriptionRequired(required) = resolver(cuesMade: cuesMade)
            .resolve(stop, for: .free)
        else {
            Issue.record("the locked stop did not resolve to the subscription")
            return
        }

        #expect(required == .plus)
        #expect(cuesMade.value == 0)
    }

    @Test("A full-screen stop becomes a phone session")
    func phoneStopBecomesASession() {
        let stop = DialStop.standingFor(Self.technique)

        guard case let .phoneSession(launch) = resolver().resolve(stop, for: .free) else {
            Issue.record("the full-screen stop did not become a phone session")
            return
        }

        #expect(launch.model.technique.slug == Self.technique.slug)
    }

    @Test("A discreet stop becomes a wrist handoff without creating phone cues")
    func discreetStopBecomesAWristHandoff() {
        let cuesMade = Counter()
        let stop = discreetStop(for: Self.technique)

        guard case let .wristHandoff(handoff) = resolver(cuesMade: cuesMade)
            .resolve(stop, for: .free)
        else {
            Issue.record("the discreet stop did not become a wrist handoff")
            return
        }

        #expect(handoff.occasionSlug == "through-this-meeting")
        #expect(handoff.techniqueSlug == Self.technique.slug)
        #expect(cuesMade.value == 0)
    }

    @Test("A stop's dialled technique is the one the phone plays")
    func reusesTheStopsDialledTechnique() {
        let overrides = TechniqueOverrides(
            stages: [StageDialling(phaseDurationsMs: [4000, 4000], cycles: 7)],
            rounds: 2
        )
        let stop = DialStop.standingFor(Self.technique, dialled: overrides)

        guard case let .phoneSession(launch) = resolver().resolve(stop, for: .free) else {
            Issue.record("the dialled stop did not become a phone session")
            return
        }

        #expect(launch.model.technique.stages.first?.cycles == 7)
        #expect(launch.model.technique.recommendedRounds == 2)
    }

    @Test("A prescribed register reaches the phone timeline")
    func carriesRegister() {
        let stop = occasionStop(register: .playful)

        guard case let .phoneSession(launch) = resolver().resolve(stop, for: .free) else {
            Issue.record("the occasion did not become a phone session")
            return
        }

        #expect(launch.register == .playful)
        #expect(launch.model.timeline.register == .playful)
    }

    @Test("An occasion's slug reaches the phone session")
    func carriesOccasion() {
        let stop = occasionStop(register: .plain)

        guard case let .phoneSession(launch) = resolver().resolve(stop, for: .free) else {
            Issue.record("the occasion did not become a phone session")
            return
        }

        #expect(launch.occasionSlug == "bedtime-story")
    }

    @Test("A child protocol owns its rhythm, words, and warning")
    func childProtocolOwnsItsSessionPresentation() throws {
        let occasion = Occasion(
            slug: "with-your-child",
            name: "With your child",
            summary: "",
            prescription: Prescription(
                techniqueSlug: Self.technique.slug,
                goal: .calm,
                surface: .fullScreen,
                register: .playful,
                duration: .seconds(90),
                phaseDurations: [.seconds(3), .seconds(5)],
                safetyNote: "Do not add holds or fast breathing."
            )
        )
        let stop = DialStop(
            technique: Self.technique,
            origin: .occasion(occasion),
            band: .occasions,
            saved: nil
        )

        guard case let .phoneSession(launch) = resolver().resolve(stop, for: .free) else {
            Issue.record("the child protocol did not become a phone session")
            return
        }

        let stage = try #require(launch.model.technique.stages.first)
        #expect(stage.phases.map(\.duration) == [.seconds(3), .seconds(5)])
        #expect(stage.cycles == 11)
        #expect(launch.model.timeline.beats.first?.instruction == "Smell the flower")
        #expect(launch.model.timeline.beats.first(where: { $0.kind == .exhale })?.instruction
            == "Blow out the candle")
        #expect(launch.model.title == "With your child")
        #expect(launch.model.warning?.key == "occasion/with-your-child")
        #expect(launch.model.warning?.title == "With your child")
    }

    private func occasionStop(register: CopyRegister) -> DialStop {
        let occasion = Occasion(
            slug: "bedtime-story",
            name: "Bedtime story",
            summary: "",
            prescription: Prescription(
                techniqueSlug: Self.technique.slug,
                goal: .sleep,
                surface: .fullScreen,
                register: register,
                duration: .seconds(32)
            )
        )
        return DialStop(
            technique: Self.technique,
            origin: .occasion(occasion),
            band: .occasions,
            saved: nil
        )
    }

    private func discreetStop(for technique: Technique) -> DialStop {
        let occasion = Occasion(
            slug: "through-this-meeting",
            name: "Through this meeting",
            summary: "",
            prescription: Prescription(
                techniqueSlug: technique.slug,
                goal: .calm,
                surface: .discreet,
                duration: .seconds(300)
            )
        )
        return DialStop(
            technique: technique,
            origin: .occasion(occasion),
            band: .occasions,
            saved: nil
        )
    }

    private final class Counter {
        var value = 0
    }
}

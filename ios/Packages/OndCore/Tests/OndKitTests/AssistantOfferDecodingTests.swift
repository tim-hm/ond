import Foundation
import OndAPI
@testable import OndKit
import Testing

@Suite("Decoding the chat's exercise offer")
struct AssistantOfferDecodingTests {
    private func response(
        _ payload: Ond_V1_ChatResponse.OneOf_Payload?
    ) -> Ond_V1_ChatResponse {
        var response = Ond_V1_ChatResponse()
        response.source = .model
        response.payload = payload
        return response
    }

    /// The wire's per-stage dialling lands as `TechniqueOverrides`' parallel
    /// arrays, shape for shape — this mapping is what lets `dialled(with:)`
    /// apply an offer with no defensive branch.
    @Test("An offer maps onto TechniqueOverrides shape for shape")
    func mapsOverrides() {
        var stage = Ond_V1_StageDialling()
        stage.phaseDurationsMs = [4000, 6000]
        stage.cycles = 8
        var overrides = Ond_V1_ExerciseOverrides()
        overrides.stages = [stage]
        overrides.rounds = 2
        var wire = Ond_V1_ExerciseOffer()
        wire.techniqueSlug = "extended-exhale"
        wire.overrides = overrides

        let offer = AssistantRepository.offer(response(.offer(wire)))

        #expect(offer == ExerciseOffer(
            techniqueSlug: "extended-exhale",
            overrides: TechniqueOverrides(
                phaseDurationsMs: [[4000, 6000]],
                stageCycles: [8],
                rounds: 2
            )
        ))
    }

    /// A text chunk carries no offer, and absence decodes as absence.
    @Test("A text payload has no offer")
    func textHasNoOffer() {
        #expect(AssistantRepository.offer(response(.text("prose"))) == nil)
        #expect(AssistantRepository.offer(response(nil)) == nil)
    }

    /// The tolerant half of the boundary: a malformed offer is dropped rather
    /// than failing the stream — it decorates a reply that is already good.
    @Test("An empty slug drops the offer")
    func emptySlugDrops() {
        var wire = Ond_V1_ExerciseOffer()
        wire.techniqueSlug = ""
        #expect(AssistantRepository.offer(response(.offer(wire))) == nil)
    }

    /// A card is optional decoration on prose that has already arrived. A draft
    /// this build cannot represent is therefore dropped rather than failing the
    /// stream and taking the reply with it.
    @Test("An unreadable saved exercise drops only the card")
    func unreadableSavedExerciseDrops() {
        let unreadable = Ond_V1_TechniqueDraft()

        #expect(AssistantRepository.proposal(response(.savedExercise(unreadable))) == nil)
    }

    /// No overrides message — or an empty one — is "as catalogued", which is
    /// nil overrides, not a zeroed dialling.
    @Test("Absent or empty overrides decode as curated")
    func absentOverridesAreCurated() {
        var bare = Ond_V1_ExerciseOffer()
        bare.techniqueSlug = "box-breathing"
        #expect(
            AssistantRepository.offer(response(.offer(bare)))
                == ExerciseOffer(techniqueSlug: "box-breathing", overrides: nil)
        )

        var emptied = bare
        emptied.overrides = Ond_V1_ExerciseOverrides()
        #expect(
            AssistantRepository.offer(response(.offer(emptied)))?.overrides == nil
        )
    }

    /// The read-back direction: a turn that carried an offer sends its slug —
    /// and only its slug — so the server can annotate the history without
    /// ever trusting the numbers.
    @Test("A turn's offer rides back as its slug alone")
    func offeredSlugRidesBack() {
        let turn = ChatTurn(
            role: .coach,
            text: "Try this.",
            proposal: .exercise(ExerciseOffer(
                techniqueSlug: "box-breathing",
                overrides: TechniqueOverrides(
                    phaseDurationsMs: [[4000]],
                    stageCycles: [4],
                    rounds: 1
                )
            ))
        )

        let wire = AssistantRepository.wire(turn)

        #expect(wire.offeredSlug == "box-breathing")
        #expect(wire.text == "Try this.")
        #expect(wire.role == .coach)

        let plain = AssistantRepository.wire(ChatTurn(role: .person, text: "hello"))
        #expect(plain.offeredSlug.isEmpty)
    }
}

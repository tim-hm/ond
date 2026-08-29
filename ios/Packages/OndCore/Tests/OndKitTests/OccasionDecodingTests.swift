import Foundation
import OndAPI
@testable import OndKit
import Testing

/// The `ListRoutes` boundary. Everything here is about what the app refuses to
/// represent: a route it decodes wrongly is a promise about a session it then
/// breaks, and the surface is the field that promise is made in.
@Suite("Decoding proto occasions into domain types")
struct OccasionDecodingTests {
    private static func protoPrescription(
        goal: Ond_V1_TechniqueGoal = .calm,
        surface: Ond_V1_DeliverySurface = .fullScreen,
        register: Ond_V1_CopyRegister = .plain,
        durationMs: UInt32 = 180_000,
        phaseDurationsMs: [UInt32] = [],
        safetyNote: String = ""
    ) -> Ond_V1_Prescription {
        var prescription = Ond_V1_Prescription()
        prescription.techniqueSlug = "box-breathing"
        prescription.goal = goal
        prescription.surface = surface
        prescription.register = register
        prescription.durationMs = durationMs
        prescription.phaseDurationsMs = phaseDurationsMs
        prescription.safetyNote = safetyNote
        return prescription
    }

    private static func protoOccasion(
        prescription: Ond_V1_Prescription? = protoPrescription()
    ) -> Ond_V1_Occasion {
        var occasion = Ond_V1_Occasion()
        occasion.slug = "before-a-presentation"
        occasion.name = "Before a presentation"
        occasion.summary = "Steady the nerves."
        if let prescription {
            occasion.prescription = prescription
        }
        return occasion
    }

    private static func response(
        occasions: [Ond_V1_Occasion] = [protoOccasion()],
        progression: [Ond_V1_ProgressionStep] = []
    ) -> Ond_V1_ListRoutesResponse {
        var response = Ond_V1_ListRoutesResponse()
        response.occasions = occasions
        response.progression = progression
        return response
    }

    /// One occasion carrying `prescription`, as a whole response — the shape
    /// every rejection test below wants, spelled once.
    private static func routing(
        _ prescription: Ond_V1_Prescription
    ) -> Ond_V1_ListRoutesResponse {
        response(occasions: [protoOccasion(prescription: prescription)])
    }

    @Test("A seeded occasion decodes with its whole prescription")
    func aWholeOccasionDecodes() throws {
        let occasions = try OccasionCatalogue(proto: Self.response())
        let occasion = try #require(occasions.occasions.first)

        #expect(occasion.slug == "before-a-presentation")
        #expect(occasion.prescription.techniqueSlug == "box-breathing")
        #expect(occasion.prescription.goal == .calm)
        #expect(occasion.prescription.surface == .fullScreen)
        #expect(occasion.prescription.duration == .seconds(180))
        #expect(occasion.prescription.phaseDurations.isEmpty)
        #expect(occasion.prescription.safetyNote == nil)
    }

    @Test("A protocol carries its own rhythm and safety note")
    func aProtocolCarriesItsSessionOverrides() throws {
        let occasions = try OccasionCatalogue(proto: Self.routing(Self.protoPrescription(
            register: .playful,
            durationMs: 90000,
            phaseDurationsMs: [3000, 5000],
            safetyNote: "Do not add holds."
        )))
        let prescription = try #require(occasions.occasions.first?.prescription)

        #expect(prescription.phaseDurations == [.seconds(3), .seconds(5)])
        #expect(prescription.safetyNote == "Do not add holds.")
    }

    @Test("The discreet surface survives the wire")
    func theDiscreetSurfaceDecodes() throws {
        let occasions = try OccasionCatalogue(proto: Self
            .routing(Self.protoPrescription(surface: .discreet)))

        #expect(occasions.occasions.first?.prescription.surface == .discreet)
    }

    /// A surface this build has no name for is not a session it may guess at:
    /// degrading to full screen would put an animation on somebody's screen in
    /// the meeting the route promised to be quiet through.
    @Test("An unreadable surface fails the decode rather than degrading")
    func anUnreadableSurfaceIsRejected() {
        for surface in [Ond_V1_DeliverySurface.unspecified, .UNRECOGNIZED(7)] {
            #expect(throws: TechniqueRepositoryError.self) {
                try OccasionCatalogue(proto: Self.routing(Self.protoPrescription(surface: surface)))
            }
        }
    }

    /// The deliberate asymmetry with the surface above, asserted through the same
    /// boundary so the prescription decoder is shown to carry the field at all. A
    /// register this build has no name for costs a tone of voice; dropping the
    /// route over it would take a working exercise off the board to avoid saying
    /// "Breathe in" instead of something warmer.
    @Test("An unreadable register degrades to plain and keeps its route")
    func anUnreadableRegisterDegradesToPlain() throws {
        let playful = try OccasionCatalogue(proto: Self
            .routing(Self.protoPrescription(register: .playful)))
        #expect(playful.occasions.first?.prescription.register == .playful)

        for register in [Ond_V1_CopyRegister.unspecified, .plain, .UNRECOGNIZED(99)] {
            let occasions = try OccasionCatalogue(proto: Self
                .routing(Self.protoPrescription(register: register)))

            #expect(occasions.occasions.count == 1, "the route survives \(register)")
            #expect(occasions.occasions.first?.prescription.register == .plain)
        }
    }

    /// An occasion snapshot written before the register and protocol rhythm
    /// existed still decodes with their neutral values. `CachedReferenceRepository`
    /// prefers the disk snapshot to the bundled seed, so a required key would not
    /// degrade the register — it would drop the whole file back to the seed,
    /// silently undoing whatever the server last sent.
    @Test("A cached route from before the session overrides still decodes")
    func anOlderSnapshotStillDecodes() throws {
        let current = try OccasionCatalogue(proto: Self.response())
        // The old snapshot is this one with the key deleted, not a literal: every
        // other field then matches what the encoder actually writes, which a
        // hand-typed fixture gets wrong silently. Sorted, so the key has one
        // spelling to delete — unsorted output puts `register` last as often as
        // not, and the removal would silently no-op and assert nothing.
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let encoded = try #require(String(bytes: encoder.encode(current), encoding: .utf8))
        let older = encoded
            .replacingOccurrences(of: "\"phaseDurations\":[],", with: "")
            .replacingOccurrences(of: "\"register\":\"plain\",", with: "")

        #expect(older != encoded, "the register should have been in the snapshot to remove")

        let restored = try JSONDecoder().decode(OccasionCatalogue.self, from: Data(older.utf8))

        #expect(restored.occasions.first?.prescription.register == .plain)
        #expect(restored.occasions.first?.prescription.phaseDurations.isEmpty == true)
        #expect(restored == current)
    }

    @Test("An occasion with no goal this app knows fails the decode")
    func anUnreadableGoalIsRejected() {
        #expect(throws: TechniqueRepositoryError.self) {
            try OccasionCatalogue(proto: Self.routing(Self.protoPrescription(goal: .unspecified)))
        }
    }

    @Test("An occasion asking for no time at all fails the decode")
    func aZeroLengthPrescriptionIsRejected() {
        #expect(throws: TechniqueRepositoryError.self) {
            try OccasionCatalogue(proto: Self.routing(Self.protoPrescription(durationMs: 0)))
        }
    }

    @Test("A zero-length protocol phase fails the decode")
    func aZeroLengthProtocolPhaseIsRejected() {
        #expect(throws: TechniqueRepositoryError.self) {
            try OccasionCatalogue(proto: Self.routing(Self.protoPrescription(phaseDurationsMs: [
                3000,
                0,
            ])))
        }
    }

    @Test("An occasion whose prescription never arrived fails the decode")
    func aMissingPrescriptionIsRejected() {
        #expect(throws: TechniqueRepositoryError.self) {
            try OccasionCatalogue(proto: Self
                .response(occasions: [Self.protoOccasion(prescription: nil)]))
        }
    }

    @Test("Progression steps decode in the order they were sent")
    func theProgressionKeepsItsOrder() throws {
        var first = Ond_V1_ProgressionStep()
        first.techniqueSlug = "box-breathing"
        first.note = "Start here."
        var second = Ond_V1_ProgressionStep()
        second.techniqueSlug = "physiological-sigh"

        let occasions = try OccasionCatalogue(
            proto: Self.response(occasions: [], progression: [first, second])
        )

        #expect(occasions.progression.map(\.techniqueSlug) == [
            "box-breathing",
            "physiological-sigh",
        ])
        #expect(occasions.progression.last?.note.isEmpty == true)
    }

    @Test("An empty response is occasions with nothing in them, not a failure")
    func anEmptyResponseIsNoOccasions() throws {
        let occasions = try OccasionCatalogue(proto: Self.response(occasions: []))

        #expect(occasions == .none)
    }
}

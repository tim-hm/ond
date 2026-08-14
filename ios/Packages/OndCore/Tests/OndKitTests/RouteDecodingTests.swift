import Foundation
import OndAPI
@testable import OndKit
import Testing

/// The `ListRoutes` boundary. Everything here is about what the app refuses to
/// represent: a route it decodes wrongly is a promise about a session it then
/// breaks, and the surface is the field that promise is made in.
@Suite("Decoding proto routes into domain types")
struct RouteDecodingTests {
    private static func protoPrescription(
        goal: Ond_V1_TechniqueGoal = .calm,
        surface: Ond_V1_DeliverySurface = .fullScreen,
        register: Ond_V1_CopyRegister = .plain,
        durationMs: UInt32 = 180_000
    ) -> Ond_V1_Prescription {
        var prescription = Ond_V1_Prescription()
        prescription.techniqueSlug = "box-breathing"
        prescription.goal = goal
        prescription.surface = surface
        prescription.register = register
        prescription.durationMs = durationMs
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
        let routes = try Routes(proto: Self.response())
        let occasion = try #require(routes.occasions.first)

        #expect(occasion.slug == "before-a-presentation")
        #expect(occasion.prescription.techniqueSlug == "box-breathing")
        #expect(occasion.prescription.goal == .calm)
        #expect(occasion.prescription.surface == .fullScreen)
        #expect(occasion.prescription.duration == .seconds(180))
    }

    @Test("The discreet surface survives the wire")
    func theDiscreetSurfaceDecodes() throws {
        let routes = try Routes(proto: Self.routing(Self.protoPrescription(surface: .discreet)))

        #expect(routes.occasions.first?.prescription.surface == .discreet)
    }

    /// A surface this build has no name for is not a session it may guess at:
    /// degrading to full screen would put an animation on somebody's screen in
    /// the meeting the route promised to be quiet through.
    @Test("An unreadable surface fails the decode rather than degrading")
    func anUnreadableSurfaceIsRejected() {
        for surface in [Ond_V1_DeliverySurface.unspecified, .UNRECOGNIZED(7)] {
            #expect(throws: TechniqueRepositoryError.self) {
                try Routes(proto: Self.routing(Self.protoPrescription(surface: surface)))
            }
        }
    }

    /// The deliberate asymmetry with the surface above, asserted through the same
    /// boundary so the prescription decoder is shown to carry the field at all.
    ///
    /// A register this build has no name for costs a tone of voice; dropping the
    /// route over it would take a working exercise off the board to avoid saying
    /// "Breathe in" instead of something warmer.
    @Test("An unreadable register degrades to plain and keeps its route")
    func anUnreadableRegisterDegradesToPlain() throws {
        let playful = try Routes(proto: Self.routing(Self.protoPrescription(register: .playful)))
        #expect(playful.occasions.first?.prescription.register == .playful)

        for register in [Ond_V1_CopyRegister.unspecified, .plain, .UNRECOGNIZED(99)] {
            let routes = try Routes(proto: Self.routing(Self.protoPrescription(register: register)))

            #expect(routes.occasions.count == 1, "the route survives \(register)")
            #expect(routes.occasions.first?.prescription.register == .plain)
        }
    }

    /// A routes snapshot written before the register existed still decodes, and
    /// reads as plain.
    ///
    /// `CachedReferenceRepository` restores routes from disk and seeds nothing in
    /// their place, so a required key here would not degrade the register — it
    /// would cost home its occasions offline until a launch repaired the file.
    @Test("A cached route from before the register still decodes")
    func anOlderSnapshotStillDecodes() throws {
        let current = try Routes(proto: Self.response())
        // The old snapshot is this one with the key deleted, rather than a
        // literal: every other field then still matches whatever shape the
        // encoder actually writes, which is the thing a hand-typed fixture gets
        // wrong and a decoder never tells you about.
        // Sorted, so the key has one spelling to delete: unsorted output puts
        // `register` last as often as not, and the removal below would silently
        // no-op and assert nothing.
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let encoded = try #require(String(bytes: encoder.encode(current), encoding: .utf8))
        let older = encoded.replacingOccurrences(of: "\"register\":\"plain\",", with: "")

        #expect(older != encoded, "the register should have been in the snapshot to remove")

        let restored = try JSONDecoder().decode(Routes.self, from: Data(older.utf8))

        #expect(restored.occasions.first?.prescription.register == .plain)
        #expect(restored == current)
    }

    @Test("An occasion with no goal this app knows fails the decode")
    func anUnreadableGoalIsRejected() {
        #expect(throws: TechniqueRepositoryError.self) {
            try Routes(proto: Self.routing(Self.protoPrescription(goal: .unspecified)))
        }
    }

    @Test("An occasion asking for no time at all fails the decode")
    func aZeroLengthPrescriptionIsRejected() {
        #expect(throws: TechniqueRepositoryError.self) {
            try Routes(proto: Self.routing(Self.protoPrescription(durationMs: 0)))
        }
    }

    @Test("An occasion whose prescription never arrived fails the decode")
    func aMissingPrescriptionIsRejected() {
        #expect(throws: TechniqueRepositoryError.self) {
            try Routes(proto: Self.response(occasions: [Self.protoOccasion(prescription: nil)]))
        }
    }

    @Test("Progression steps decode in the order they were sent")
    func theProgressionKeepsItsOrder() throws {
        var first = Ond_V1_ProgressionStep()
        first.techniqueSlug = "box-breathing"
        first.note = "Start here."
        var second = Ond_V1_ProgressionStep()
        second.techniqueSlug = "physiological-sigh"

        let routes = try Routes(
            proto: Self.response(occasions: [], progression: [first, second])
        )

        #expect(routes.progression.map(\.techniqueSlug) == ["box-breathing", "physiological-sigh"])
        #expect(routes.progression.last?.note.isEmpty == true)
    }

    @Test("An empty response is routes with nothing in them, not a failure")
    func anEmptyResponseIsNoRoutes() throws {
        let routes = try Routes(proto: Self.response(occasions: []))

        #expect(routes == .none)
    }
}

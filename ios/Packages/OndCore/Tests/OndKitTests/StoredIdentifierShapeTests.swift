import Foundation
@testable import OndKit
import Testing

/// What is already on the devices people are using.
///
/// A slug that started encoding as an object rather than a string would fail no
/// build and no screen — it would read as no schedules and no history on the
/// next launch. These fixtures are the JSON written before the slugs had types.
@Suite("Stored identifier shapes")
struct StoredIdentifierShapeTests {
    private static let decoder = JSONDecoder()

    private static func encoded(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try String(bytes: encoder.encode(value), encoding: .utf8) ?? ""
    }

    /// A session written before this change still reads back, and writes back
    /// out in the same shape — a bare string, never a wrapped object.
    @Test func a_stored_session_still_decodes_and_re_encodes_flat() throws {
        let stored = """
        {"breathCount":8,"completed":true,"cyclesCompleted":4,"durationMs":60000,\
        "id":"00000000-0000-0000-0000-000000000001","occasionSlug":"through-this-meeting",\
        "startedAt":800000000,"surface":"discreet","techniqueSlug":"box-breathing"}
        """

        let record = try Self.decoder.decode(SessionRecord.self, from: Data(stored.utf8))

        #expect(record.techniqueSlug == "box-breathing")
        #expect(record.occasionSlug == "through-this-meeting")
        #expect(try Self.encoded(record).contains("\"techniqueSlug\":\"box-breathing\""))
        #expect(try Self.encoded(record).contains("\"occasionSlug\":\"through-this-meeting\""))
    }

    /// A session recorded before the provenance fields existed carries no
    /// occasion, and the absent key must stay absent rather than becoming an
    /// encoded empty wrapper.
    @Test func a_session_without_an_occasion_keeps_the_key_absent() throws {
        let stored = """
        {"breathCount":8,"completed":true,"cyclesCompleted":4,"durationMs":60000,\
        "id":"00000000-0000-0000-0000-000000000002","startedAt":800000000,\
        "techniqueSlug":"box-breathing"}
        """

        let record = try Self.decoder.decode(SessionRecord.self, from: Data(stored.utf8))

        #expect(record.occasionSlug == nil)
        #expect(record.surface == .fullScreen)
        #expect(try !Self.encoded(record).contains("occasionSlug"))
    }

    /// A stored schedule list is what the reminder dial and every local
    /// notification are rebuilt from on launch.
    @Test func a_stored_schedule_still_decodes_and_re_encodes_flat() throws {
        let stored = """
        {"fromDial":true,"hour":7,"id":"00000000-0000-0000-0000-000000000003",\
        "isEnabled":true,"minute":0,"techniqueName":"Box breathing",\
        "techniqueSlug":"box-breathing","weekdays":[1]}
        """

        let schedule = try Self.decoder.decode(Schedule.self, from: Data(stored.utf8))

        #expect(schedule.techniqueSlug == "box-breathing")
        #expect(try Self.encoded(schedule).contains("\"techniqueSlug\":\"box-breathing\""))
    }

    /// The dialled lengths, which are keyed by slug rather than merely carrying
    /// one. `Dictionary` encodes as a JSON object only for a `String`, an `Int`,
    /// or a `CodingKeyRepresentable` key; without that conformance on the slug
    /// this file would be rewritten as a flat array and every override anybody
    /// had dialled would fail to read back.
    @Test func stored_overrides_stay_an_object_keyed_by_slug() throws {
        let stored = """
        {"box-breathing":{"rounds":2,"stages":[{"cycles":6,"phaseDurationsMs":[4000,4000]}]}}
        """

        let overrides = try Self.decoder.decode(
            [TechniqueSlug: TechniqueOverrides].self,
            from: Data(stored.utf8)
        )

        #expect(overrides["box-breathing"]?.rounds == 2)
        #expect(overrides["box-breathing"]?.stages.first?.cycles == 6)
        #expect(try Self.encoded(overrides).hasPrefix("{\"box-breathing\":"))
    }

    /// Home's default exercise, which decides what the button starts.
    @Test func a_stored_home_choice_still_decodes_and_re_encodes_flat() throws {
        let stored = #"{"minutes":5,"slug":"coherent-breathing"}"#

        let choice = try Self.decoder.decode(HomeChoice.self, from: Data(stored.utf8))

        #expect(choice.slug == "coherent-breathing")
        #expect(choice.minutes == 5)
        #expect(try Self.encoded(choice) == stored)
    }
}

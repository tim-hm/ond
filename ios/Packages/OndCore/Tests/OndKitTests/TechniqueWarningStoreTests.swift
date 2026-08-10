import Foundation
import OndKit
import Testing

/// The per-technique warning gate: shown while unaccepted, silenceable by an
/// explicit tick, and revived by a rewording.
@MainActor
@Suite("Technique warnings")
struct TechniqueWarningStoreTests {
    private func defaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "technique-warnings.\(UUID().uuidString)"))
    }

    private func technique(note: String? = "Sitting down only.") -> Technique {
        Technique(
            id: "wim-hof",
            slug: "wim-hof",
            name: "Wim Hof rounds",
            summary: "",
            goal: .energy,
            stages: [Stage(
                phases: [Phase(kind: .inhale, duration: .seconds(2))],
                cycles: 1
            )],
            recommendedRounds: 1,
            safetyNote: note
        )
    }

    @Test("A technique without a note never warns")
    func noNoteNoWarning() throws {
        let store = try TechniqueWarningStore(defaults: defaults())

        #expect(store.needsWarning(for: technique(note: nil)) == false)
    }

    @Test("A note warns until it is silenced, not merely accepted")
    func acceptanceAloneDoesNotSilence() throws {
        let store = try TechniqueWarningStore(defaults: defaults())
        let technique = technique()

        #expect(store.needsWarning(for: technique))

        store.accept(technique, silenced: false)
        #expect(
            store.needsWarning(for: technique),
            "an un-ticked acceptance was for that session, not the next one"
        )

        store.accept(technique, silenced: true)
        #expect(store.needsWarning(for: technique) == false)
    }

    @Test("A silence survives a relaunch")
    func silencePersists() throws {
        let defaults = try defaults()
        let technique = technique()

        TechniqueWarningStore(defaults: defaults).accept(technique, silenced: true)

        #expect(TechniqueWarningStore(defaults: defaults).needsWarning(for: technique) == false)
    }

    @Test("Rewording the note lifts the silence")
    func rewordedNoteWarnsAgain() throws {
        let defaults = try defaults()
        let store = TechniqueWarningStore(defaults: defaults)

        store.accept(technique(note: "Sitting down only."), silenced: true)

        #expect(
            store.needsWarning(for: technique(note: "Sitting or lying down only.")),
            "the silence was an agreement to words the note no longer says"
        )
    }

    @Test("Un-ticking the box on a later acceptance lifts an old silence")
    func laterAcceptanceCanUnsilence() throws {
        let store = try TechniqueWarningStore(defaults: defaults())
        let technique = technique()

        store.accept(technique, silenced: true)
        store.accept(technique, silenced: false)

        #expect(store.needsWarning(for: technique))
    }

    @Test("What was accepted is recorded — the words and the moment")
    func keepsTheRecord() throws {
        let store = try TechniqueWarningStore(defaults: defaults())
        let accepted = Date(timeIntervalSince1970: 1_700_000_000)

        store.accept(technique(), silenced: true, at: accepted)

        let record = try #require(store.accepted["wim-hof"])
        #expect(record.text == "Sitting down only.")
        #expect(record.acceptedAt == accepted)
        #expect(record.silenced)
    }

    @Test("Erasure forgets every acceptance, on disk and in memory")
    func erasureForgets() async throws {
        let defaults = try defaults()
        let store = TechniqueWarningStore(defaults: defaults)
        let technique = technique()

        store.accept(technique, silenced: true)
        await store.erase()

        #expect(store.needsWarning(for: technique))
        #expect(TechniqueWarningStore(defaults: defaults).needsWarning(for: technique))
    }
}

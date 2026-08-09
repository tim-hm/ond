import Foundation
@testable import OndKit
import Testing

/// The shared semantics every defaults-backed store inherits: decode failures
/// preserve the payload rather than destroy it, and an erasure takes the
/// preserved copy with the live one.
@Suite("Defaults JSON store")
struct DefaultsJSONStoreTests {
    private struct Record: Codable, Equatable {
        var name: String
    }

    private func defaults(_ name: String) -> UserDefaults {
        let suite = "defaults-json-store-tests.\(name)"
        let created = UserDefaults(suiteName: suite)
        created?.removePersistentDomain(forName: suite)
        return created ?? .standard
    }

    private func store(over suite: UserDefaults) -> DefaultsJSONStore<Record> {
        DefaultsJSONStore(
            key: "test.record",
            what: "the record",
            category: "tests",
            defaults: suite
        )
    }

    @Test("Nothing stored loads as nil, so each owner chooses its own empty state")
    func absentValueLoadsNil() {
        #expect(store(over: defaults("absent")).load() == nil)
    }

    @Test("What was saved is what loads")
    func roundTrips() {
        let store = store(over: defaults("roundtrip"))
        store.save(Record(name: "kept"))
        #expect(store.load() == Record(name: "kept"))
    }

    @Test("An unreadable payload loads as nil but is copied aside, not destroyed")
    func unreadablePayloadIsPreserved() {
        let suite = defaults("unreadable")
        let garbage = Data("not a record".utf8)
        suite.set(garbage, forKey: "test.record")

        #expect(store(over: suite).load() == nil)
        #expect(
            suite.data(forKey: "test.record.unreadable") == garbage,
            "the copy is what a later decoder or a post-mortem still finds"
        )
        #expect(
            suite.data(forKey: "test.record") == garbage,
            "the live key keeps the payload too, so a decoding version reads it back by itself"
        )
    }

    @Test("Erasure removes the value and the preserved copy together")
    func erasureTakesBothKeys() {
        let suite = defaults("erase")
        suite.set(Data("not a record".utf8), forKey: "test.record")
        let store = store(over: suite)
        _ = store.load()

        store.erase()
        #expect(suite.data(forKey: "test.record") == nil)
        #expect(suite.data(forKey: "test.record.unreadable") == nil)
    }
}

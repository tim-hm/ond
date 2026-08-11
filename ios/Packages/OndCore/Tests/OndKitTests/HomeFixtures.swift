import Foundation
@testable import OndKit

/// What every suite about home needs and none of them is about.
///
/// Four suites — the dial's routing, its authored band, the deck's order, and
/// starring from an exercise's own screen — each had a private `session(_:)`
/// spelling the same seven fields, and the copies had already drifted on the fields
/// nobody asserts. `SessionRecord` is a wire-shaped type, so a new field on it was
/// four identical edits.
///
/// Deliberately only the record. The routes each suite declares stay each suite's
/// own: `HomeDialTests` needs occasions that differ only in surface, the authored
/// and starred suites need the smallest set that still leads somewhere, and folding
/// those into one fixture would make a test's setup something a reader has to go and
/// look up to know what it is testing.
enum HomeFixtures {
    /// One finished session of `slug`, at whatever moment the caller's rule turns on
    /// — defaulted to now, which is what a suite that only counts them means.
    static func session(_ slug: String, at startedAt: Date = .now) -> SessionRecord {
        SessionRecord(
            techniqueSlug: slug,
            startedAt: startedAt,
            duration: .seconds(120),
            cyclesCompleted: 4,
            breathCount: 8,
            completed: true
        )
    }
}

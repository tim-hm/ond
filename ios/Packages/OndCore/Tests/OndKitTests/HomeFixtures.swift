import Foundation
@testable import OndKit

/// What every suite about home needs and none of them is about. Four suites
/// each had a private `session(_:)` spelling the same seven fields, and the
/// copies had drifted on the fields nobody asserts. Deliberately only the
/// record: the routes stay each suite's own, so a test's setup is not
/// something a reader must go and look up to know what it is testing.
enum HomeFixtures {
    /// One session of `slug`, at whatever moment the caller's rule turns on —
    /// defaulted to now and finished, which is what a suite that only counts
    /// them means. `completed: false` is the ended-early record the state
    /// line's honesty rule turns on.
    static func session(
        _ slug: String = "box-breathing",
        at startedAt: Date = .now,
        lasting duration: Duration = .seconds(120),
        completed: Bool = true
    ) -> SessionRecord {
        SessionRecord(
            techniqueSlug: slug,
            startedAt: startedAt,
            duration: duration,
            cyclesCompleted: 4,
            breathCount: 8,
            completed: completed
        )
    }
}

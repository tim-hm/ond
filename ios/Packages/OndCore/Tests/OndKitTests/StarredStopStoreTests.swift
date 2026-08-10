import Foundation
@testable import OndKit
import Testing

/// The first thing on home somebody curates, and so the first that has to survive a
/// relaunch and not survive a deletion.
@MainActor
@Suite("Starring a card")
struct StarredStopStoreTests {
    private func defaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: "stars.\(UUID().uuidString)")
        return defaults ?? .standard
    }

    @Test("A fresh install has nothing starred")
    func aFreshInstallHasNoStars() {
        #expect(StarredStopStore(defaults: defaults()).starred.isEmpty)
    }

    @Test("Starring and unstarring are the same tap")
    func togglingIsSymmetric() {
        let store = StarredStopStore(defaults: defaults())

        store.toggle("occasions/winding-down")
        #expect(store.isStarred("occasions/winding-down"))

        store.toggle("occasions/winding-down")
        #expect(!store.isStarred("occasions/winding-down"))
    }

    /// What the composer calls, and it must not be `toggle`: editing an exercise saves
    /// the same slug a second time, and a toggle there would quietly take it off the
    /// shortlist it had just been put on.
    @Test("Starring the same card twice leaves it starred")
    func starringIsIdempotent() {
        let store = StarredStopStore(defaults: defaults())

        store.star("yours/my-own-square")
        store.star("yours/my-own-square")

        #expect(store.starred == ["yours/my-own-square"])
    }

    /// The point of a store rather than a piece of view state: a shortlist that had to
    /// be rebuilt every launch would not be one.
    @Test("A star outlives the process that made it")
    func starsSurviveARelaunch() {
        let defaults = defaults()
        let first = StarredStopStore(defaults: defaults)

        first.toggle("startHere/box-breathing")
        first.toggle("occasions/winding-down")

        let second = StarredStopStore(defaults: defaults)
        #expect(second.starred == ["startHere/box-breathing", "occasions/winding-down"])
    }

    /// What somebody chose to keep in front of them is as personal as what they
    /// breathed. Both halves, as `PersonalStore` requires: the disk and this process.
    @Test("A deletion leaves no shortlist behind, in memory or on disk")
    func erasingForgetsEveryStar() async {
        let defaults = defaults()
        let store = StarredStopStore(defaults: defaults)
        store.toggle("startHere/box-breathing")

        await store.erase()

        #expect(store.starred.isEmpty)
        #expect(StarredStopStore(defaults: defaults).starred.isEmpty)
    }
}

import Foundation
@testable import OndKit
import Testing

/// The one thing on Home somebody curates, and so the first that has to survive a
/// relaunch and not survive a deletion.
@MainActor
@Suite("Starring a stop")
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
        #expect(store.starred.contains("occasions/winding-down"))

        store.toggle("occasions/winding-down")
        #expect(!store.starred.contains("occasions/winding-down"))
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

    /// One exercise can be starred as more than one card — a rung of Start here and
    /// the catalogue entry behind it — so the control that says "this exercise is on
    /// my board" has to take that back in one press. Pressing it once per band would
    /// be the control lying about what it meant the first time.
    @Test("Unstarring a set clears every card it names and leaves the rest")
    func unstarringClearsASet() {
        let store = StarredStopStore(defaults: defaults())
        store.star("startHere/box-breathing")
        store.star("everything/box-breathing")
        store.star("occasions/winding-down")

        store.unstar(["startHere/box-breathing", "everything/box-breathing"])

        #expect(store.starred == ["occasions/winding-down"])
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

    // MARK: starring a stop rather than an id

    private static let box = SeededCatalogue.technique("box-breathing")

    private static let rung = DialStop.standalone(
        [box], in: .startHere, dialled: [:]
    )[0]

    private static let winding = DialStop.occasions(
        of: OccasionCatalogue(occasions: [
            Occasion(
                slug: "winding-down",
                name: "Winding down",
                summary: "",
                prescription: Prescription(
                    techniqueSlug: "box-breathing",
                    goal: .sleep,
                    surface: .fullScreen,
                    duration: .seconds(300)
                )
            ),
        ]),
        resolvedBy: DialStop.indexed([box]),
        dialled: [:]
    )[0]

    /// The defect `DialStop.ids(standingFor:)` was written to name. Star Box
    /// Breathing on its own screen and a rung's row must read as starred rather
    /// than draw an empty star over it.
    @Test("An exercise starred under any band reads as starred on every row for it")
    func aStarOnAnyBandIsTheExerciseStarred() {
        let store = StarredStopStore(defaults: defaults())
        store.star(DialStop.id(of: Self.box))

        #expect(store.isStarred(Self.rung))
        #expect(!store.starred.contains(Self.rung.id))
    }

    /// Pressing a filled star three times to clear three bands would be the
    /// control lying about what it meant the first time.
    @Test("Unstarring a row takes back every id standing for that exercise")
    func unstarringClearsEveryStandingId() {
        let store = StarredStopStore(defaults: defaults())
        store.star(DialStop.id(of: Self.box))
        store.star("startHere/box-breathing")

        store.toggle(Self.rung)

        #expect(store.starred.isDisjoint(with: DialStop.ids(standingFor: Self.box)))
        #expect(!store.isStarred(Self.rung))
    }

    /// A protocol is keyed by the moment, and "Winding down" is a different
    /// promise from the exercise it prescribes — so starring one must not star
    /// or clear the other.
    @Test("Starring a protocol is not starring the exercise it prescribes")
    func aProtocolStarsOnlyItself() {
        let store = StarredStopStore(defaults: defaults())

        store.toggle(Self.winding)
        #expect(store.isStarred(Self.winding))
        #expect(!store.isStarred(Self.rung))

        store.star(DialStop.id(of: Self.box))
        store.toggle(Self.rung)
        #expect(store.isStarred(Self.winding))
    }
}
